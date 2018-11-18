module sharedlib;

import core.stdc.errno;
import core.stdc.string;
import core.atomic;
import core.sync.mutex;
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


/// To guard all uses libdl our own mutex.
/// This code is stallen from std.concurrency.
private @property shared(Mutex) initOnceLock()
{
    static shared Mutex lock;
    if (auto mtx = atomicLoad!(MemoryOrder.acq)(lock))
        return mtx;
    auto mtx = new shared Mutex;
    if (cas(&lock, cast(shared) null, mtx))
        return mtx;
    return atomicLoad!(MemoryOrder.acq)(lock);
}


/// Whole error in libdl is shared at global state.
/// So need to guard all uses of libdl with mutex.
private void dlerrorWithFunc(string funcName)(bool delegate() del)
{
    if (!del())
    {
        auto m = initOnceLock();
        m.lock();
        scope (exit) m.unlock();
        const errorMsg = dlerror();
        if (errorMsg !is null)
            errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
        errnoEnforce(false, "failed to " ~ funcName ~ " by unknown reason.");
    }
}

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
        dlerrorWithFunc!"dlopen(3)"(() {
                this.handle = dlopen(filename.toStringz, flags);
                return this.handle !is null;
            });
    }

    ~this()
    {
        if (this.handle !is null)
            close();
    }

    ///
    void close()
    {
        dlerrorWithFunc!"dlclose(3)"(() {
                const ret = dlclose(this.handle);
                return ret == 0;
            });
    }

    ///
    auto get(in string symbolName)
    {
        void* symbol;
        dlerrorWithFunc!"dlsym(3)"(() {
                symbol = dlsym(this.handle, symbolName.toStringz);
                return symbol !is null;
            });
        return symbol;
    }

    // utility for getting the adress of library loaded.
    void* getLoadedAddr()
    {
        return cast(void*) *cast(const size_t*) this.handle;
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
