
/*
 * AUTHOR
 *
 * Rob Mueller <cpan@robm.fastmail.fm>
 *
 * COPYRIGHT AND LICENSE
 *
 * Copyright (C) 2003 by FastMail IP Partners
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the same terms as Perl itself. 
 * 
*/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <stdarg.h>
#include "mmap_cache.h"
#include "mmap_cache_internals.h"

char* _mmc_get_def_share_filename(mmap_cache * cache)
{
  return def_share_file;
}

int mmc_open_cache_file(mmap_cache* cache, int * do_init) {
  int res, fh;
  struct stat statbuf;

  /* Create file if it doesn't exist */
  *do_init = 0;
  mode_t permissions = (mode_t)cache->permissions;
  fh = open(cache->share_file, O_RDWR | O_CREAT, permissions);
  if (fh == -1) {
    _mmc_set_error(cache, errno, "Opening of share file %s failed", cache->share_file);
    return -1;
  }

  struct flock fl = { .l_type = F_WRLCK, .l_whence = SEEK_SET};

  // Try to obtain an exclusive lock
  res = fcntl(fh, F_SETLKW, &fl);
  if (res == -1) {
    _mmc_set_error(cache, errno, "Locking of share file %s failed", cache->share_file);
    close(fh);
    return -1;
  }

  res = fstat(fh, &statbuf);
  if (res == -1) {
    _mmc_set_error(cache, errno, "Getting size of share file %s failed", cache->share_file);
    close(fh);
    return -1;
  }

  /* Remove if different size or remove requested */
  if (cache->init_file || (statbuf.st_size != cache->c_size)) {
    res = ftruncate(fh, 0);
    if (res == -1 && errno != ENOENT) {
      _mmc_set_error(cache, errno, "Truncating of share file %s failed", cache->share_file);
      close(fh);
      return -1;
    }

    // Fill the file with 0s
    res = ftruncate(fh, cache->c_size);
    if (res == -1) {
      _mmc_set_error(cache, errno, "Truncating of share file %s failed", cache->share_file);
      close(fh);
      return -1;
    }

    /* Later on initialise page structures */
    *do_init = 1;
  }
  fl.l_type   = F_UNLCK;
  res = fcntl(fh, F_SETLK, &fl);
  if (res == -1) {
    _mmc_set_error(cache, errno, "Unlocking of share file %s failed", cache->share_file);
    close(fh);
    return -1;
  }

  /* Automatically close cache fd on exec */
  fcntl(fh, F_SETFD, FD_CLOEXEC);

  cache->fh = fh;

  return 0;

}

/*
 * mmc_map_memory(mmap_cache * cache)
 *
 * maps the cache file into memory, and sets cache->mm_var as needed.
*/
int mmc_map_memory(mmap_cache* cache) {
  /* Map file into memory */
  cache->mm_var = mmap(0, cache->c_size, PROT_READ | PROT_WRITE, MAP_SHARED, cache->fh, 0);
  if (cache->mm_var == (void *)MAP_FAILED) {
    _mmc_set_error(cache, errno, "Mmap of shared file %s failed", cache->share_file);
    mmc_close_fh(cache);
    return -1;
  }

  return 0;
}

/*
 * mmc_unmap_memory(mmap_cache * cache)
 *
 * Unmaps cache->mm_var
*/
int mmc_unmap_memory(mmap_cache* cache) {
  int res = munmap(cache->mm_var, cache->c_size);
  if (res == -1) {
    _mmc_set_error(cache, errno, "Munmap of shared file %s failed", cache->share_file);
    return -1;
  }
  return res;
}

int mmc_close_fh(mmap_cache* cache) {
  int res = close(cache->fh);
  return res;
}

int mmc_lock_page(mmap_cache* cache, MU64 p_offset) {
  struct flock lock;
  int old_alarm, alarm_left = 10;
  int lock_res = -1;

  /* Setup fcntl locking structure */
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;
  lock.l_start = p_offset;
  lock.l_len = cache->c_page_size;

  if (cache->catch_deadlocks)
    old_alarm = alarm(alarm_left);

  while (lock_res != 0) {

    /* Lock the page (block till done, signal, or timeout) */
    lock_res = fcntl(cache->fh, F_SETLKW, &lock);

    /* Continue immediately if success */
    if (lock_res == 0) {
      if (cache->catch_deadlocks)
        alarm(old_alarm);
      break;
    }

    /* Turn off alarm for a moment */
    if (cache->catch_deadlocks)
      alarm_left = alarm(0);

    /* Some signal interrupted, and it wasn't the alarm? Rerun lock */
    if (lock_res == -1 && errno == EINTR && alarm_left) {
      if (cache->catch_deadlocks)
        alarm(alarm_left);
      continue;
    }

    /* Lock failed? */
    _mmc_set_error(cache, errno, "Lock failed");
    if (cache->catch_deadlocks)
      alarm(old_alarm);
    return -1;
  }

  return 0;
}

int mmc_unlock_page(mmap_cache * cache) {
  struct flock lock;

  /* Setup fcntl locking structure */
  lock.l_type = F_UNLCK;
  lock.l_whence = SEEK_SET;
  lock.l_start = cache->p_offset;
  lock.l_len = cache->c_page_size;

  /* And unlock page */
  fcntl(cache->fh, F_SETLKW, &lock);

  /* Set to bad value while page not locked */
  cache->p_cur = NOPAGE;

  return 0;
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

  va_start(ap, error_string);

  /* Make sure it's terminated */
  errbuf[1023] = '\0';

  /* Start with error string passed */
  vsnprintf(errbuf, 1023, error_string, ap);

  /* Add system error code if passed */
  if (err) {
    strncat(errbuf, ": ", 1024);
    strncat(errbuf, strerror(err), 1023);
  }

  /* Save in cache object */
  cache->last_error = errbuf;

  va_end(ap);

  return 0;
}
