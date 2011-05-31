/*
 * AUTHOR
 *
 * Ash Berlin <ash@cpan.org>
 *
 * Based on code by
 * Rob Mueller <cpan@robm.fastmail.fm>
 *
 * COPYRIGHT AND LICENSE
 *
 * Copyright (C) 2007 by Ash Berlin
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the same terms as Perl itself. 
 * 
*/

#include <Windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdarg.h>


#include "mmap_cache.h"
#include "mmap_cache_internals.h"

#ifdef _MSC_VER
#if _MSC_VER <= 1310
#define vsnprintf _vsnprintf
#endif
#endif

char* _mmc_get_def_share_filename(mmap_cache * cache)
{
    int ret;
    static char buf[MAX_PATH];

    ret = GetTempPath(MAX_PATH, buf);
    if (ret > MAX_PATH)
    {
        _mmc_set_error(cache, GetLastError(), "Unable to get temp path");
        return NULL;
    }    
    return strcat(buf, "sharefile");    
}

int mmc_open_cache_file(mmap_cache* cache, int* do_init) {
  int i;
  void *tmp;
    HANDLE fh, fileMap, findHandle;
    WIN32_FIND_DATA statbuf;

    *do_init = 0;
        
    findHandle = FindFirstFile(cache->share_file, &statbuf);
        
    /* Create file if it doesn't exist */    
    if (findHandle == INVALID_HANDLE_VALUE) {
        fh = CreateFile(cache->share_file, GENERIC_WRITE, FILE_SHARE_WRITE, NULL,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
                
        if (fh == INVALID_HANDLE_VALUE) {
            _mmc_set_error(cache, GetLastError(), "Create of share file %s failed", cache->share_file);
            return -1;
        }
        
        /* Fill file with 0's */
        tmp = malloc(cache->c_page_size);
        if (!tmp) {
            _mmc_set_error(cache, GetLastError(), "Malloc of tmp space failed");
            return -1;
        }
        
        memset(tmp, 0, cache->c_page_size);
        for (i = 0; i < cache->c_num_pages; i++) {
            DWORD tmpOut;
            WriteFile(fh, tmp, cache->c_page_size, &tmpOut, NULL);
        }
        free(tmp);
        
        /* Later on initialise page structures */
        *do_init = 1;
        
        CloseHandle(fh);
        
    } else {
        FindClose(findHandle);
    
        if (cache->init_file || (statbuf.nFileSizeLow != cache->c_size)) {
            *do_init = 1;
    
            fh = CreateFile(cache->share_file, GENERIC_WRITE, FILE_SHARE_WRITE, NULL,
			    CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
                            
            if (fh == INVALID_HANDLE_VALUE) {
                _mmc_set_error(cache, GetLastError(), "Truncate of existing share file %s failed", cache->share_file);
                return -1;
            }
            CloseHandle(fh);
        }
    }
    
    fh = CreateFile(cache->share_file,         // File Name 
             GENERIC_READ|GENERIC_WRITE,       // Desired Access
             FILE_SHARE_READ|FILE_SHARE_WRITE, // Share mode
             NULL,                             // Security Rights
             OPEN_EXISTING,                    // Creation Mode
             FILE_ATTRIBUTE_TEMPORARY,         // File Attribs
             NULL);                            // Template File    
    
    if (fh == INVALID_HANDLE_VALUE) {
        _mmc_set_error(cache, GetLastError(), "Open of share file \"%s\" failed", cache->share_file);
        return -1;  
    }

    cache->fh = fh;
    return 0;
}

int mmc_map_memory(mmap_cache * cache) {
    HANDLE fileMap = CreateFileMapping(cache->fh, NULL, PAGE_READWRITE, 0, cache->c_size, NULL);
    if (fileMap == NULL) {
        _mmc_set_error(cache, GetLastError(), "CreateFileMapping of %s failed", cache->share_file);
        CloseHandle(cache->fh);
        return -1;
    }
    
    cache->mm_var = MapViewOfFile(fileMap, FILE_MAP_WRITE|FILE_MAP_READ, 0,0,0);
    if (cache->mm_var == NULL) {
        _mmc_set_error(cache, GetLastError(), "Mmap of shared file %s failed", cache->share_file);
        CloseHandle(fileMap);
        CloseHandle(cache->fh);
        return -1;
        
    }
    /* If I read the docs right, this will do nothing untill the mm_var is unmapped */
    if (CloseHandle(fileMap) == FALSE) {
        _mmc_set_error(cache, GetLastError(), "CloseHandle(fileMap) on shared file %s failed", cache->share_file);
        UnmapViewOfFile(cache->mm_var);
        CloseHandle(fileMap);
        CloseHandle(cache->fh);
        return -1;
    }
  return 0;
}

int mmc_close_fh(mmap_cache* cache) {
  int ret = CloseHandle(cache->fh);
  cache->fh = NULL;
  return ret;
}

int mmc_unmap_memory(mmap_cache* cache) {
  int res = UnmapViewOfFile(cache->mm_var);
  if (res == -1) {
    _mmc_set_error(cache, GetLastError(), "Unmmap of shared file %s failed", cache->share_file);
  }
  return res;
}

int mmc_lock_page(mmap_cache* cache, MU32 p_offset) {
    OVERLAPPED lock;
    DWORD lock_res, bytesTransfered;
    memset(&lock, 0, sizeof(lock));
    lock.Offset = p_offset;
    lock.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
  
    if (LockFileEx(cache->fh, 0, 0, cache->c_page_size, 0, &lock) == 0) {
        _mmc_set_error(cache, GetLastError(), "LockFileEx failed");
        return -1;
    }
    
    lock_res = WaitForSingleObjectEx(lock.hEvent, 10000, FALSE);
    
    if (lock_res != WAIT_OBJECT_0 || GetOverlappedResult(cache->fh, &lock, &bytesTransfered, FALSE) == FALSE) {
        CloseHandle(lock.hEvent);
        _mmc_set_error(cache, GetLastError(), "Overlapped Lock failed");
        return -1;
    }
  return 0;
}

int mmc_unlock_page(mmap_cache* cache) {
    OVERLAPPED lock;
    memset(&lock, 0, sizeof(lock));
    lock.Offset = cache->p_offset;
    lock.hEvent = 0;
  
    UnlockFileEx(cache->fh, 0, cache->c_page_size, 0, &lock);
    
    /* Set to bad value while page not locked */
    cache->p_cur = ~0; /* ~0 = -1, but unsigned */    
}

/*
 * int _mmc_set_error(mmap_cache *cache, int err, char * error_string, ...)
 *
 * Set internal error string/state
 *
*/
int _mmc_set_error(mmap_cache *cache, int err, char * error_string, ...) {
  va_list ap;
  static char errbuf[1024];
  char *msgBuff;

  va_start(ap, error_string);

  /* Make sure it's terminated */
  errbuf[1023] = '\0';

  /* Start with error string passed */
  vsnprintf(errbuf, 1023, error_string, ap);

  /* Add system error code if passed */
  if (err) {
    strncat(errbuf, ": ", 1024);
    FormatMessage(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | 
        FORMAT_MESSAGE_FROM_SYSTEM,
        NULL,
        err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        (LPTSTR) &msgBuff,
        0, NULL );    
    strncat(errbuf, msgBuff, 1023);
    LocalFree(msgBuff);
  }

  /* Save in cache object */
  cache->last_error = errbuf;

  va_end(ap);

  return 0;
}

