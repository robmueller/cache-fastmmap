
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
 * mmap_cache
 *
 * Uses an mmap'ed file to act as a shared memory interprocess cache
 * 
 * The C interface is quite explicit in it's use, in that you have to
 * call individual functions to hash a key, lock a page, and find a
 * value. This allows a simpler higher level interface to be written
 *
 *  #include <mmap_cache.h>
 *  
 *  mmap_cache * cache = mmc_new();
 *  cache->param = val;
 *  mmc_init(cache);
 *
 *  // Read a key
 *
 *  // Hash get to find page and slot
 *  mmc_hash(cache, (void *)key_ptr, (int)key_len, &hash_page, &hash_slot);
 *  // Lock page
 *  mmc_lock(cache, hash_page);
 *  // Get pointer to value data
 *  mmc_read(cache, hash_slot, (void *)key_ptr, (int)key_len, (void **)&val_ptr, (int *)val_len, &flags);
 *  // Unlock page
 *  mmc_unlock(cache);
 *
 *  // Write a key
 *
 *  // Hash get to find page and slot
 *  mmc_hash(cache, (void *)key_ptr, (int)key_len, &hash_page, &hash_slot);
 *  // Lock page
 *  mmc_lock(cache, hash_page);
 *  // Get pointer to value data
 *  mmc_write(cache, hash_slot, (void *)key_ptr, (int)key_len, (void *)val_ptr, (int)val_len);
 *  // Unlock page
 *  mmc_unlock(cache);
 *
 * DESCRIPTION
 * 
 * This class implements a shared memory cache through an mmap'ed file. It
 * uses locking to ensure multiple processes can safely access the cache
 * at the same time. It uses a basic LRU algorithm to keep the most used
 * entries in the cache.
 * 
 * It tries to be quite efficient through a number of means:
 * 
 * It uses multiple pages within a file, and uses Fcntl to only lock
 * a page at a time to reduce contention when multiple processes access
 * the cache.
 * 
 * It uses a dual level hashing system (hash to find page, then hash
 * within each page to find a slot) to make most I<read> calls O(1) and
 * fast
 * 
 * On each I<write>, if there are slots and page space available, only
 * the slot has to be updated and the data written at the end of the used
 * data space. If either runs out, a re-organisation of the page is
 * performed to create new slots/space which is done in an efficient way
 * 
 * The locking is explicitly done in the C interface, so you can create
 * a 'read_many' or 'write_many' function that reduces the number of
 * locks required
 * 
 * 
 * IMPLEMENTATION
 * 
 * Each file is made up of a number of 'pages'. The number of
 * pages and size of each page is specified when the class is
 * constructed. These values are stored in the cache class
 * and must be the same for each class connecting to the cache
 * file.
 * 
 * NumPages - Number of 'pages' in the cache
 * PageSize - Size of each 'page' in the cache
 * 
 * The layout of each page is:
 * 
 * - Magic (4 bytes) - 0x92f7e3b1 magic page start marker
 *
 * - NumSlots (4 bytes) - Number of hash slots in this page
 *
 * - FreeSlots (4 bytes) - Number of free slots left in this page.
 *   This includes all slots with a last access time of 0
 *   (empty and don't search past) or 1 (empty, but keep searching
 *   because deleted slot)
 * 
 * - OldSlots (4 bytes) - Of all the free slots, how many were in use
 *   and are now deleted. This is slots with a last access time of 1
 * 
 * - FreeData (4 bytes) - Offset to free data area to place next item
 * 
 * - FreeBytes (4 bytes) - Bytes left in free data area
 * 
 * - N Reads (4 bytes) - Number of reads performed on this page
 *
 * - N Read Hits (4 bytes) - Number of reads on this page that have hit
 *   something in the cache
 * 
 * - Slots (4 bytes * NumSlots) - Hash slots
 *
 * - Data (to end of page) - Key/value data
 * 
 * Each slot is made of:
 * 
 * - Offset (4 bytes) - offset from start of page to actual data. This
 *   is 0 if slot is empty, 1 if was used but now empty. This is needed
 *   so deletes don't require a complete rehash with the linear
 *   searching method we use
 *
 * Each data item is made of:
 *
 * - LastAccess (4 bytes) - Unix time data was last accessed
 * 
 * - ExpireTime (4 bytes) - Unix time data should expire. This is 0 if it
 *   should never expire
 * 
 * - HashValue (4 bytes) - Value key was hashed to, so we don't have to
 *   rehash on a re-organisation of the hash table
 *
 * - Flags (4 bytes) - Various flags
 * 
 * - KeyLen (4 bytes) - Length of key
 * 
 * - ValueLen (4 bytes) - Length of value
 * 
 * - Key (KeyLen bytes) - Key data
 * 
 * - Value (ValueLen bytes) - Value data
 * 
 * Each set/get/delete operation involves:
 * 
 * - Find the page for the key
 * - Lock the page
 * - Read the page header
 * - Find the hash slot for the key
 * 
 * For get's:
 * 
 * - Use linear probing to find correct key, or empty slot
 * 
 * For set's:
 * 
 * - Use linear probing to find empty slot
 * - If not enough free slots, do an 'expunge' run
 * - Store key/value at FreeData offset, update, and store in slot
 * - If not enough space at FreeData offset, do an 'expunge' run
 *    then store data
 * 
 * For delete's:
 * 
 * - Use linear probing to find correct key, or empty slot
 * - Set slot to empty (data cleaned up in expunge run)
 * 
 * An expunge run consists of:
 * 
 * - Scan slots to find used key/value parts. Remove older items
 * - If ratio used/free slots too high, increase slot count
 * - Compact key/value data into one memory block
 * - Restore and update offsets in slots
 * 
*/

/* Main cache structure passed as a pointer to each function */
typedef struct mmap_cache mmap_cache;

/* Iterator structure for iterating over items in cache */
typedef struct mmap_cache_it mmap_cache_it;

/* Unsigned 32 bit integer */
typedef unsigned int MU32;

/* Initialisation/closing/error functions */
mmap_cache * mmc_new();
int mmc_init(mmap_cache *);
int mmc_set_param(mmap_cache *, char *, char *);
int mmc_get_param(mmap_cache *, char *);
int mmc_close(mmap_cache *);
char * mmc_error(mmap_cache *);

/* Functions for find/locking a page */
int mmc_hash(mmap_cache *, void *, int, MU32 *, MU32 *);
int mmc_lock(mmap_cache *, MU32);
int mmc_unlock(mmap_cache *);
int mmc_is_locked(mmap_cache *);

/* Functions for getting/setting/deleting values in current page */
int mmc_read(mmap_cache *, MU32, void *, int, void **, int *, MU32 *);
int mmc_write(mmap_cache *, MU32, void *, int, void *, int, MU32, MU32);
int mmc_delete(mmap_cache *, MU32, void *, int, MU32 *);

/* Functions of expunging values in current page */
int mmc_calc_expunge(mmap_cache *, int, int, MU32 *, MU32 ***);
int mmc_do_expunge(mmap_cache *, int, MU32, MU32 **);

/* Functions for iterating over items in a cache */
mmap_cache_it * mmc_iterate_new(mmap_cache *);
MU32 * mmc_iterate_next(mmap_cache_it *);
void mmc_iterate_close(mmap_cache_it *);

/* Retrieve details of a cache page/entry */
void mmc_get_details(mmap_cache *, MU32 *, void **, int *, void **, int *, MU32 *, MU32 *, MU32 *);
void mmc_get_page_details(mmap_cache * cache, MU32 * nreads, MU32 * nreadhits);
void mmc_reset_page_details(mmap_cache * cache);

/* Internal functions */
int _mmc_set_error(mmap_cache *, int, char *, ...);
void _mmc_init_page(mmap_cache *, MU32);

MU32 * _mmc_find_slot(mmap_cache * , MU32 , void *, int, int );
void _mmc_delete_slot(mmap_cache * , MU32 *);

int _mmc_check_expunge(mmap_cache * , int);

int  _mmc_test_page(mmap_cache *);
int  _mmc_dump_page(mmap_cache *);


