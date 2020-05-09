





在Ubuntu18.04上编译PHP5.5.9（想要个curl.so的模块）报错，提示找不到easy.h



```BASH
# apt-get install libcurl4-gnutls-dev
# ./configure  --with-curl --enable-fpm
checking for cURL support... yes
checking if we should use cURL for url streams... no
checking for cURL in default path... not found
configure: error: Please reinstall the libcurl distribution -
    easy.h should be in <curl-dir>/include/curl/
```

实际上这个文件时存在的

```BASH
root@20200305:/usr/include# ll /usr/include/x86_64-linux-gnu/curl/
total 204
drwxr-xr-x 2 root root   4096 Apr 23 12:55 ./
drwxr-xr-x 9 root root   4096 Apr 23 12:55 ../
-rw-r--r-- 1 root root 102017 Sep  6  2019 curl.h
-rw-r--r-- 1 root root   3034 Sep  6  2019 curlver.h
-rw-r--r-- 1 root root   3473 Sep  6  2019 easy.h
-rw-r--r-- 1 root root   2071 Sep  6  2019 mprintf.h
-rw-r--r-- 1 root root  16094 Sep  6  2019 multi.h
-rw-r--r-- 1 root root   1329 Sep  6  2019 stdcheaders.h
-rw-r--r-- 1 root root  17684 Sep  6  2019 system.h
-rw-r--r-- 1 root root  42492 Sep  6  2019 typecheck-gcc.h
```

我又指定了一个curl的路径，重新编译，仍然报错。

```BASH
# ./configure  --with-curl=/usr/include/x86_64-linux-gnu/curl
checking for cURL support... yes
checking if we should use cURL for url streams... no
checking for cURL in default path... not found
configure: error: Please reinstall the libcurl distribution -
    easy.h should be in <curl-dir>/include/curl/
```

解决方法是：

```BASH
cd /usr/include
sudo ln -s x86_64-linux-gnu/curl

```







```BASH
make: *** [ext/fileinfo/libmagic/apprentice.lo] Error 1
```

是因为服务器内存不足1G。

只需要重新./configure，并在最后添加 --disable-fileinfo，然后重新make

