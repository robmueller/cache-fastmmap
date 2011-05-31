#ifndef mmap_cache_internals_h
#define mmap_cache_interanls_h

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
  MU32    p_offset;

  MU32    p_num_slots;
  MU32    p_free_slots;
  MU32    p_old_slots;
  MU32    p_free_data;
  MU32    p_free_bytes;
  MU32    p_n_reads;
  MU32    p_n_read_hits;

  int    p_changed;

  /* General page details */
  MU32    c_num_pages;
  MU32    c_page_size;
  MU32    c_size;

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
#endif  
  char * share_file;
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

/* Macros to access cache slot entries */
#define SP(s) ((MU32 *)s)

/* Offset pointer 'p' by 'o' bytes */
#define PTR_ADD(p,o) ((void *)((char *)p + o))

/* Given a data pointer, get key len, value len or combined len */
#define S_Ptr(b,s)      ((MU32 *)PTR_ADD(b, s))

#define S_LastAccess(s) (*(s+0))
#define S_ExpireTime(s) (*(s+1))
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
int mmc_lock_page(mmap_cache* cache, MU32 p_offset);
int mmc_unlock_page(mmap_cache * cache);
int mmc_close_fh(mmap_cache* cache);
int _mmc_set_error(mmap_cache *cache, int err, char * error_string, ...);
char* _mmc_get_def_share_filename(mmap_cache * cache);

#endif

