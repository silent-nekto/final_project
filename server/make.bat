cython -3 server.pyx --embed
"c:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
cl server.c /I c:\Python38\include /link c:\Python38\libs\python38.lib
