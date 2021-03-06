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
enum RTLD_LOCAL = 0;
enum RTLD_LAZY = 1;
enum RTLD_NOW = 2;
enum RTLD_GLOBAL = 3;


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
private void dlerrorWithFunc(bool delegate() del)
{
    auto m = initOnceLock();
    m.lock();
    scope (exit) m.unlock();

    if (!del())
    {
        const errorMsg = dlerror();
        if (errorMsg !is null)
            errnoEnforce(false, cast(string) errorMsg[0 .. strlen(errorMsg)]);
        errnoEnforce(false, "failed unknown reason.");
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
    this(string filename, int flags)
    {
        dlerrorWithFunc(() nothrow {
                this.handle = dlopen(filename.toStringz, flags);
                return this.handle !is null;
            });
    }

    ~this() nothrow @nogc
    {
        import core.internal.abort : abort;
        /// destructor cannot raise exception, so only call dlclose(3).
        if (this.handle !is null)
        {
            const ret = dlclose(this.handle);
            if (ret != 0)
                abort("Error: dlclose(3) failed.");
        }
    }

    ///
    void close()
    {
        dlerrorWithFunc(() nothrow {
                return dlclose(this.handle) == 0;
            });
    }

    ///
    auto get(string symbolName)
    {
        void* symbol;
        dlerrorWithFunc(() nothrow {
                symbol = dlsym(this.handle, symbolName.toStringz);
                return symbol !is null;
            });
        return symbol;
    }

    // utility for getting the adress of library loaded.
    void* getLoadedAddr() nothrow
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
