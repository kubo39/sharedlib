module sharedlib;

import core.sys.posix.unistd;
import core.sys.posix.dlfcn;

import core.stdc.errno;
import core.stdc.string;

import std.exception;


immutable int RTLD_LAZY = 1;
immutable int RTLD_NOW = 2;


/**
   This is a wrapper of UNIX-specified dynamic-linking and loading.
   See `man 3 dlopen`.
 */
struct SharedLibrary
{
    void* handle;

    this(const char* filename, int flags)
    {
        handle = dlopen(filename, flags);
        if (handle is null)
        {
            const errorMsg = dlerror();
            if (errorMsg !is null)
                errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
            errnoEnforce(false, "failed to dlopen(3) by unknown reason.");
        }
    }


    ~this()
    {
        if (handle !is null)
            close();
    }


    void close()
    {
        const ret = dlclose(handle);
        if (ret != 0)
        {
            const errorMsg = dlerror();
            if (errorMsg !is null)
                errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
            errnoEnforce(false, "failed to dlsym(3) by unknown reason.");
        }
    }


    auto get(in char* symbolName)
    {
        const symbol = dlsym(handle, symbolName);
        if (symbol is null)
        {
            const errorMsg = dlerror();
            if (errorMsg !is null)
                errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
            errnoEnforce(false, "failed to dlsym(3) by unknown reason.");
        }
        return symbol;
    }
}


unittest
{
    auto libm = new SharedLibrary("libm.so\0".ptr, RTLD_LAZY);
    auto ceil = cast(double function(double)) libm.get("ceil\0".ptr);
    assert(ceil(0.45) == 1);
}
