module sharedlib;

import core.stdc.errno;
import core.stdc.string;
import core.sys.posix.dlfcn;
import core.sys.posix.unistd;
import std.exception;
import std.string : toStringz;


version (Posix):


/**
See `man 3 dlopen`.
*/
immutable int RTLD_LOCAL = 0;
immutable int RTLD_LAZY = 1;
immutable int RTLD_NOW = 2;
immutable int RTLD_GLOBAL = 3;


/**
   This is a wrapper of UNIX-specified dynamic loading.
   See `man 3 dlopen`.
 */
struct SharedLibrary
{
    void* handle;

    ///
    this(in string filename, int flags)
    {
        handle = dlopen(filename.toStringz, flags);
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

    ///
    void close()
    {
        const ret = dlclose(handle);
        if (ret != 0)
        {
            const errorMsg = dlerror();
            if (errorMsg !is null)
                errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
            errnoEnforce(false, "failed to dlclose(3) by unknown reason.");
        }
    }

    ///
    auto get(in string symbolName)
    {
        const symbol = dlsym(handle, symbolName.toStringz);
        if (symbol is null)
        {
            const errorMsg = dlerror();
            if (errorMsg !is null)
                errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
            errnoEnforce(false, "failed to dlsym(3) by unknown reason.");
        }
        return symbol;
    }

    // utility for getting the adress of library loaded.
    void* getLoadedAddr()
    {
        return cast(void*) *cast(const size_t*) handle;
    }
}


@system unittest
{
    version (linux)
    {
        // Using libm.so gots invalid ELF Header.
        string libm = "libm.so.6";
    }
    else version (OSX)
    {
        string libm = "libm.dylib";
    }

    {
        auto lib = new SharedLibrary(libm, RTLD_LAZY);
        auto ceil = cast(double function(double)) lib.get("ceil");
        assert(ceil(0.45) == 1);
    }

    {
        auto lib = new SharedLibrary(libm, RTLD_LAZY);
        const addr = lib.getLoadedAddr();
        assert(addr !is null);
    }
}
