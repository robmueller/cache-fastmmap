#ifndef mmap_cache_internals_h
#define mmap_cache_internals_h

#ifdef DEBUG
#define ASSERT(x) assert(x)
#include <assert.h>
#else
#define ASSERT(x)
#endif

#ifdef WIN32
#include <windows.h>
#endif

/* Cache structure */
struct mmap_cache {

  /* Current page details */
  void * p_base;
  MU32 * p_base_slots;
  MU32    p_cur;
  MU64    p_offset;

  MU32    p_num_slots;
  MU32    p_free_slots;
  MU32    p_old_slots;
  MU32    p_free_data;
  MU32    p_free_bytes;
  MU32    p_n_reads;
  MU32    p_n_read_hits;

  int    p_changed;
  /* Current page's magic has been switched to P_MAGIC_DIRTY for an
   * in-progress update; mmc_unlock switches it back */
  int    p_dirty;
  /* Current page's structure failed a check; mmc_unlock reinitialises
   * it instead of saving the header back */
  int    p_corrupt;
  /* Set by mmc_lock/mmc_unlock when they reinitialised a page, so the
   * caller can report it. Cleared at the start of the next mmc_lock */
  int    page_repaired;
  /* Total pages reinitialised by this process since open */
  MU32   repaired_pages;

  /* General page details */
  MU32    c_num_pages;
  MU32    c_page_size;
  MU64    c_size;

  /* Pointer to mmapped area */
  void * mm_var;

  /* Cache general details */
  MU32    start_slots;
  MU32    expire_time;
  int     catch_deadlocks;
  int     enable_stats;

  /* Share mmap file details */
#ifdef WIN32
  HANDLE fh;
#else    
  int    fh;
  MU64   inode;
#endif  
  char * share_file;
  int    permissions;
  int    init_file;
  int    test_file;
  int    cache_not_found;

  /* Last error string */
  char * last_error;

};

struct mmap_cache_it {
  mmap_cache * cache;
  MU32         p_cur;
  MU32 *       slot_ptr;
  MU32 *       slot_ptr_end;
};

/* Macros to access page entries */
#define PP(p) ((MU32 *)p)

#define P_Magic(p) (*(PP(p)+0))
#define P_NumSlots(p) (*(PP(p)+1))
#define P_FreeSlots(p) (*(PP(p)+2))
#define P_OldSlots(p) (*(PP(p)+3))
#define P_FreeData(p) (*(PP(p)+4))
#define P_FreeBytes(p) (*(PP(p)+5))
#define P_NReads(p) (*(PP(p)+6))
#define P_NReadHits(p) (*(PP(p)+7))

#define P_HEADERSIZE 32

/* Page start marker. The low bit is cleared while a process holds the
 * page locked and is changing its structure, and set again before it
 * unlocks. A page found with P_MAGIC_DIRTY after acquiring the lock was
 * left mid-update by a process that died holding it (fcntl locks die
 * with their owner), so its contents can't be trusted and it is
 * reinitialised. Any other value means this isn't a page of ours. */
#define P_MAGIC        0x92f7e3b1
#define P_MAGIC_DIRTY  0x92f7e3b0

/* Make the store ordering visible to another process that later takes
 * the page lock, so the marker is written before the structure changes
 * it covers and cleared only after they are complete */
#if defined(__GNUC__) || defined(__clang__)
#define MMC_BARRIER() __sync_synchronize()
#else
#define MMC_BARRIER()
#endif
#define P_SetMagic(p, m) do { MMC_BARRIER(); *(volatile MU32 *)(p) = (m); MMC_BARRIER(); } while (0)

/* Macros to access cache slot entries */
#define SP(s) ((MU32 *)s)

/* Offset pointer 'p' by 'o' bytes */
#define PTR_ADD(p,o) ((void *)((char *)p + o))

/* Given a data pointer, get key len, value len or combined len */
#define S_Ptr(b,s)      ((MU32 *)PTR_ADD(b, s))

#define S_LastAccess(s) (*(s+0))
#define S_ExpireOn(s)   (*(s+1))
#define S_SlotHash(s)   (*(s+2))
#define S_Flags(s)      (*(s+3))
#define S_KeyLen(s)     (*(s+4))
#define S_ValLen(s)     (*(s+5))

#define S_KeyPtr(s)     ((void *)(s+6))
#define S_ValPtr(s)     (PTR_ADD((void *)(s+6), S_KeyLen(s)))

/* Length of slot data including key and value data */
#define S_SlotLen(s)    (sizeof(MU32)*6 + S_KeyLen(s) + S_ValLen(s))
#define KV_SlotLen(k,v) (sizeof(MU32)*6 + k + v)
/* Found key/val len to nearest 4 bytes */
#define ROUNDLEN(l)     ((l) += 3 - (((l)-1) & 3))  

/* Externs from mmap_cache.c */ 
extern char * def_share_file;
extern MU32    def_init_file;
extern MU32    def_test_file;
extern MU32    def_expire_time;
extern MU32    def_c_num_pages;
extern MU32    def_c_page_size;
extern MU32    def_start_slots;
extern char* _mmc_get_def_share_filename(mmap_cache * cache);

/* Platform specific functions defined in unix.c | win32.c */
int mmc_open_cache_file(mmap_cache* cache, int * do_init);
int mmc_map_memory(mmap_cache* cache);
int mmc_unmap_memory(mmap_cache* cache);
int mmc_lock_page(mmap_cache* cache, MU64 p_offset);
int mmc_unlock_page(mmap_cache * cache, MU64 p_offset);
int mmc_check_fh(mmap_cache* cache);
int mmc_close_fh(mmap_cache* cache);
int _mmc_set_error(mmap_cache *cache, int err, char * error_string, ...);
char* _mmc_get_def_share_filename(mmap_cache * cache);

#endif

