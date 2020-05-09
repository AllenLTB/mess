# bash乐居部署LDAP，使用cn=config目录格式配置

> 需求：思科ASA配置SSL VPN，用户存储在2台OpenLDAP，这两台OpenLDAP使用MirrorMode进行同步，此次需要将原有的LDAP进行迁移。 
> 下面文档中，除了个别配置在每个服务器有略不同，其余大部分配置都可以直接两台新服务器上直接执行。

**Table of Contents**
[TOC]

## 安装软件

```bash
yum -y install openldap openldap-servers openldap-clients openldap-devel compat-openldap
```

## 配置日志

```bash
##将这些配置添加到/etc/rsyslog.conf文件中
# openldap log
local4.*                                                /var/log/openldap.log

##重启rsyslog服务
systemctl restart rsyslog
```

## 初始操作

```bash
cp -r /etc/openldap/slapd.d/ /etc/openldap/slapd.d.bak
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap: /var/lib/ldap/
echo 'BASE dc=ljldap,dc=com' >> /etc/openldap/ldap.conf
echo 'URI ldap://127.0.0.1' >> /etc/openldap/ldap.conf
systemctl start slapd
```

## 定义suffix, rootdn, rootpw

```bash
# slappasswd -s 123456
{SSHA}h8Qhbe5n9kDMl8Dyl/5XJpTMOXoJTmf/

cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=ljldap,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
delete: olcRootDN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootDN
olcRootDN: cn=Admin,dc=ljldap,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: {SSHA}h8Qhbe5n9kDMl8Dyl/5XJpTMOXoJTmf/
EOF
```

## 导入schema

```bash
##默认情况下core.ldif已经被引入了，所以此处忽略。
ldapadd -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/corba.ldif
ldapadd -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/inetorgperson.ldif
```

## 让openldap支持syncrepl

```bash
##加载syncprov.la模块
cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModuleLoad: /usr/lib64/openldap/syncprov.la
EOF
```

## 允许接收LDAPv2绑定请求

```bash
cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=config
add: olcAllows
olcAllows: bind_v2
EOF
```

## 指定搜索操作最大返回的条目数为5000

```bash
cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcSizeLimit
olcSizeLimit: 5000
EOF
```

## 添加entryUUID与entryCSN的索引

```bash
cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
add: olcDbIndex
olcDbIndex: entryUUID eq
olcDbIndex: entryCSN eq
EOF
```

## 设置olcServerID

```bash
##每个服务器的ID都不一样
cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 1
EOF
```

## 创建域及OU

```bash
cat << EOF | ldapadd -x -H ldap://127.0.0.1 -D "cn=Admin,dc=ljldap,dc=com" -w 123456
dn: dc=ljldap,dc=com
dc: ljldap
objectclass: top
objectclass: domain

dn: ou=vpn,dc=ljldap,dc=com
ou: vpn
objectclass: top
objectclass: organizationalUnit
EOF
```

## 创建用于SyncRepl的用户

因为想要对vpn.leju.com中的条目进行同步，所以不要使用vpn.ljldap.com下面的用户作为SyncRepl用户。
独立用户的目的是为了保证安全，如果使用rootdn的话，别人直接通过配置文件就能获取rootdn的密码。

```bash
# slappasswd -s 123456
{SSHA}zl+/vjxQ8ndR3trl5O1z68EdPOVFBpCc

cat << EOF | ldapadd -x -H ldap://127.0.0.1 -D "cn=Admin,dc=ljldap,dc=com" -w 123456
dn: cn=replicator,dc=ljldap,dc=com
cn: replicator
mail: replicator@leju.com
uid: 5054844
objectClass: inetOrgPerson
sn: replicatior
telephoneNumber: 11111
title: manager
userPassword: {SSHA}zl+/vjxQ8ndR3trl5O1z68EdPOVFBpCc
EOF
```

## 创建用于SyncRepl用户的访问控制

```bash
cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to dn.children="dc=ljldap,dc=com"
  by dn.base="cn=replicator,dc=ljldap,dc=com" read
  by anonymous auth
EOF
```

## 设置SyncRepl，模式为MirrorMode

```bash
##两台服务器都是provider，他们的配置一样，除了ldapuri
cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: olcOverlay={2}syncprov,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcSyncProvConfig
objectClass: olcOverlayConfig
olcOverlay: {2}syncprov
olcSpSessionLog: 100
EOF

cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl:
  rid=001
  provider=ldap://10.208.3.20:389
  binddn="cn=replicator,dc=ljldap,dc=com"
  bindmethod=simple
  credentials=123456
  searchbase="ou=vpn,dc=ljldap,dc=com"
  type=refreshAndPersist
  retry="5 +"
  timeout=1
EOF

cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcMirrorMode
olcMirrorMode: TRUE
EOF
```

## 导出旧LDAP中的条目

```bash
##导出的条目中会有dn: ou=vpn,dc=ljldap,dc=com这个条目，但是因为上面创建了这个OU，所以需要在userdb.ldif文件中将这个条目注释掉。然后将文件拷贝到新服务器上(也可以通过-s children只匹配该DN下的所有子条目）。
ldapsearch -x -H ldap://10.208.3.18 -D "cn=Admin,dc=ljldap,dc=com" -w 123456 -b "ou=vpn,dc=ljldap,dc=com" > userdb.ldif

```

## 导入旧LDAP中的条目

```bash
##在其中一台服务器上执行导入操作即可，所有的条目信息都会被同步到另一台服务器
ldapadd -x -H ldap://10.208.3.20 -D "cn=Admin,dc=ljldap,dc=com" -w 123456 -f /tmp/userdb.ldif
```

## 最终效果

```bash
##原来的条目数量
# ldapsearch -x -H ldap://10.208.3.18 -D "cn=Admin,dc=ljldap,dc=com" -w 123456 -b "ou=vpn,dc=ljldap,dc=com" | wc -l
27480


##两台新服务器的条目数量和都和原来的LDAP一样了
# ldapsearch -x -H ldap://10.208.3.19 -D "cn=Admin,dc=ljldap,dc=com" -w 123456 -b "ou=vpn,dc=ljldap,dc=com" | wc -l
27480
# ldapsearch -x -H ldap://10.208.3.20 -D "cn=Admin,dc=ljldap,dc=com" -w 123456 -b "ou=vpn,dc=ljldap,dc=com" | wc -l
27480
```

**两台新OpenLDAP服务器的后端配置**

```bash
[10.208.3.19 root@test-1:~]
# cat /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif 
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 ca0424b4
dn: olcDatabase={2}hdb
objectClass: olcDatabaseConfig
objectClass: olcHdbConfig
olcDatabase: {2}hdb
olcDbDirectory: /var/lib/ldap
olcDbIndex: objectClass eq,pres
olcDbIndex: ou,cn,mail,surname,givenname eq,pres,sub
olcDbIndex: entryUUID eq
olcDbIndex: entryCSN eq
structuralObjectClass: olcHdbConfig
entryUUID: 7ddec50a-9348-1039-984b-6b589f2ae9c4
creatorsName: cn=config
createTimestamp: 20191104121510Z
olcSuffix: dc=ljldap,dc=com
olcRootDN: cn=Admin,dc=ljldap,dc=com
olcRootPW:: e1NTSEF9aDhRaGJlNW45a0RNbDhEeWwvNVhKcFRNT1hvSlRtZi8=
olcSizeLimit: 5000
olcAccess: {0}to dn.children="dc=ljldap,dc=com" by dn.base="cn=replicator,dc
 =ljldap,dc=com" read by anonymous auth
olcSyncrepl: {0}rid=001 provider=ldap://10.208.3.20:389 binddn="cn=replicato
 r,dc=ljldap,dc=com" bindmethod=simple credentials=123456 searchbase="ou=vpn
 ,dc=ljldap,dc=com" type=refreshAndPersist retry="5 +" timeout=1
olcMirrorMode: TRUE
entryCSN: 20191104121845.024494Z#000000#001#000000
modifiersName: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
modifyTimestamp: 20191104121845Z

[10.208.3.20 root@localhost:~]
# cat /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 5dae8093
dn: olcDatabase={2}hdb
objectClass: olcDatabaseConfig
objectClass: olcHdbConfig
olcDatabase: {2}hdb
olcDbDirectory: /var/lib/ldap
olcDbIndex: objectClass eq,pres
olcDbIndex: ou,cn,mail,surname,givenname eq,pres,sub
olcDbIndex: entryUUID eq
olcDbIndex: entryCSN eq
structuralObjectClass: olcHdbConfig
entryUUID: 7eebae72-9348-1039-8024-0b3b11d6a474
creatorsName: cn=config
createTimestamp: 20191104121512Z
olcSuffix: dc=ljldap,dc=com
olcRootDN: cn=Admin,dc=ljldap,dc=com
olcRootPW:: e1NTSEF9aDhRaGJlNW45a0RNbDhEeWwvNVhKcFRNT1hvSlRtZi8=
olcSizeLimit: 5000
olcAccess: {0}to dn.children="dc=ljldap,dc=com" by dn.base="cn=replicator,dc
 =ljldap,dc=com" read by anonymous auth
olcSyncrepl: {0}rid=001 provider=ldap://10.208.3.19:389 binddn="cn=replicato
 r,dc=ljldap,dc=com" bindmethod=simple credentials=123456 searchbase="ou=vpn
 ,dc=ljldap,dc=com" type=refreshAndPersist retry="5 +" timeout=1
olcMirrorMode: TRUE
entryCSN: 20191104122058.062810Z#000000#001#000000
modifiersName: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
modifyTimestamp: 20191104122058Z
```