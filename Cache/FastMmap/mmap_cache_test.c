#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#if !defined(WIN32) || defined(CYGWIN)
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#endif

#ifdef DEBUG
#define ASSERT(x) assert(x)
#include <assert.h>
#else
#define ASSERT(x)
#endif

#ifndef WIN32
#include <sys/wait.h>
#else
#include <stdlib.h>
#include <stdio.h>
#include <windows.h>
double last_rand;
double drand48(void) {
    last_rand = rand() / (double)(RAND_MAX+1);
    
    ASSERT(last_rand < 1);
    return last_rand;
}
#endif

#include <time.h>
#include "mmap_cache.h"

void * Get(mmap_cache * cache, void * key_ptr, int key_len, int * val_len) {
  int found;
  void * val_ptr, * val_rtn_ptr = 0;
  MU32 hash_page, hash_slot, flags;

  /* Hash key to get page and slot */
  mmc_hash(cache, key_ptr, key_len, &hash_page, &hash_slot);

  /* Get and lock the page */
  mmc_lock(cache, hash_page);

  /* Get value data pointer */
  found = mmc_read(cache, hash_slot, key_ptr, key_len, &val_ptr, val_len, &flags);

  /* If not found, use undef */
  if (found == -1) {

  } else {

    /* Put into our own memory */
    val_rtn_ptr = (void *)malloc(*val_len);
    memcpy(val_rtn_ptr, val_ptr, *val_len);
  }

  mmc_unlock(cache);

  return val_rtn_ptr;
}

void Set(mmap_cache * cache, void * key_ptr, int key_len, void * val_ptr, int val_len) {
  MU32 hash_page, hash_slot, flags = 0, new_num_slots, ** expunge_items = 0;
  int num_expunge;

  /* Hash key to get page and slot */
  mmc_hash(cache, key_ptr, key_len, &hash_page, &hash_slot);

  /* Get and lock the page */
  mmc_lock(cache, hash_page);

  num_expunge = mmc_calc_expunge(cache, 2, key_len + val_len, &new_num_slots, &expunge_items);
  if (expunge_items) {
    mmc_do_expunge(cache, num_expunge, new_num_slots, expunge_items);
  }

  /* Get value data pointer */
  mmc_write(cache, hash_slot, key_ptr, key_len, val_ptr, val_len, 60, flags);

  mmc_unlock(cache);
}

char * rand_str(int nchar) {
  unsigned char * buf = (unsigned char *)malloc(nchar + 1);
  int i;

  for (i = 0; i < nchar; i++) {
    buf[i] = (char)(rand() % 26) + 'A';
  }
  buf[i] = 0;

  return (char *)buf;
}

char buf[65537];

int BasicTests(mmap_cache * cache) {
  int val_len, i;
  void * val_ptr;

  printf("Basic tests\n");

  /* Test empty */
  ASSERT(!Get(cache, "", 0, &val_len));
  ASSERT(!Get(cache, " ", 0, &val_len));
  for (i = 0; i < 65536; i++) { buf[i] = ' '; }
  ASSERT(!Get(cache, buf, 1024, &val_len));
  ASSERT(!Get(cache, buf, 65536, &val_len));

  /* Test basic store/get on key sizes */
  Set(cache, "", 0, "abc", 3);
  ASSERT(!memcmp(val_ptr = Get(cache, "", 0, &val_len), "abc", 3) && val_len == 3);
  free(val_ptr);
  Set(cache, " ", 1, "def", 3);
  ASSERT(!memcmp(val_ptr = Get(cache, " ", 1, &val_len), "def", 3) && val_len == 3);
  free(val_ptr);
  Set(cache, buf, 1024, "ghi", 3);
  ASSERT(!memcmp(val_ptr = Get(cache, buf, 1024, &val_len), "ghi", 3) && val_len == 3);
  free(val_ptr);

  /* Bigger than page size - shouldn't work */
  Set(cache, buf, 65536, "jkl", 3);
  ASSERT(!Get(cache, buf, 65536, &val_len));

  /* Test basic store/get on value sizes */
  Set(cache, "abc", 3, "", 0);
  ASSERT((val_ptr = Get(cache, "abc", 3, &val_len)) && val_len == 0);
  free(val_ptr);

  Set(cache, "def", 3, "x", 1);
  ASSERT(!memcmp(val_ptr = Get(cache, "def", 3, &val_len), "x", 1) && val_len == 1);
  free(val_ptr);

  for (i = 0; i < 1024; i++) { buf[i] = 'y'; }
  buf[0] = 'z'; buf[1023] = 'w';
  Set(cache, "ghi", 3, buf, 1024);
  ASSERT(!memcmp(val_ptr = Get(cache, "ghi", 3, &val_len), buf, 1024) && val_len == 1024);
  free(val_ptr);

  /* Bigger than page size - shouldn't work */
  Set(cache, "jkl", 3, buf, 65536);
  ASSERT(!Get(cache, "jkl", 3, &val_len));

  return 0;
}

int LinearTests(mmap_cache * cache) {
  int i, gl;
  char * str1, * str2, * str3;

  printf("Linear tests\n");

  for (i = 0; i < 100000; i++) {
    str1 = rand_str(10);
    str2 = rand_str(10);

    Set(cache, str1, strlen(str1)+1, str2, strlen(str2)+1);
    str3 = Get(cache, str1, strlen(str1)+1, &gl);
    ASSERT(strlen(str2)+1 == gl);
    ASSERT(!memcmp(str2, str3, strlen(str2)+1));

    free(str1);
    free(str2);
    free(str3);

    if (i % 1000 == 0) {
      printf("%d\n", i);
    }
  }
}

int EdgeTests() {
  return 0;
}

typedef struct key_list {
  int n_keys;
  int buf_size;
  char ** keys;
} key_list;

key_list * kl_new() {
  key_list * kl = (key_list *)malloc(sizeof(key_list));
  kl->buf_size = 8;
  kl->keys = (char **)malloc(sizeof(char *) * kl->buf_size);
  kl->n_keys = 0;

  return kl;
}

void kl_push(key_list * kl, char * key) {
  if (kl->n_keys < kl->buf_size) {
    kl->keys[kl->n_keys++] = key;
    return;
  }

  kl->buf_size *= 2;
  kl->keys = (char **)realloc(kl->keys, sizeof(char *) * kl->buf_size);
  kl->keys[kl->n_keys++] = key;
  return;
}

void kl_free(key_list * kl) {
  int i;

  for (i = 0; i < kl->n_keys; i++) {
    free(kl->keys[i]);
  }
}

int urand_fh = 0;

void RandSeed() {
#ifdef WIN32
	//randomize();
#else
  char buf[8];

  if (!urand_fh) {
    urand_fh = open("/dev/urandom", O_RDONLY);
  }

  read(urand_fh, buf, 8);

  srand48(*(long int *)buf);
#endif
}

int RepeatMixTests(mmap_cache * cache, double ratio, key_list * kl) {
  int i, val_len;
  int read = 0, read_hit = 0;
  char valbuf[256];

  printf("Repeat mix tests\n");

  for (i = 0; i < 10000; i++) {

    /* Read/write ratio */
    if (drand48() < ratio) {
      /* Pick a key from known written ones */
      char * k = kl->keys[(int)(drand48() * kl->n_keys)];
      void * v = Get(cache, k, strlen(k), &val_len);
      read++;

      /* Skip if not found in cache */
      if (!v) { continue; }
      read_hit++;

      /* Offset of 10 past first chars of value are key */
      memcpy(valbuf, v+10, strlen(k));
      valbuf[strlen(k)] = '\0';
      ASSERT(!memcmp(valbuf, k, strlen(k)));

      free(v);

    } else {
      char * k = rand_str(10 + (int)(drand48() * 10));
      char * v = rand_str(10);
      char * ve = rand_str((int)(drand48() * 200));
      strcpy(valbuf, v);
      strcat(valbuf, k);
      strcat(valbuf, ve);

      kl_push(kl, k);
      Set(cache, k, strlen(k), valbuf, strlen(valbuf));

      free(ve);
      free(v);
    }
  }

  if (read) {
    printf("Read hit pct: %5.3f\n", (double)read_hit/read);
  }

  return 1;
}

void IteratorTests(mmap_cache * cache) {
  MU32 * entry_ptr;
  void * key_ptr, * val_ptr;
  int key_len, val_len;
  MU32 last_access, expire_time, flags;
  mmap_cache_it * it = mmc_iterate_new(cache);

  printf("Iterator tests\n");

  while ((entry_ptr = mmc_iterate_next(it))) {
    mmc_get_details(cache, entry_ptr,
      &key_ptr, &key_len, &val_ptr, &val_len,
      &last_access, &expire_time, &flags);

    ASSERT(key_len >= 10 && key_len <= 20);
    ASSERT(val_len >= 20 && val_len <= 240);
    ASSERT(last_access >= 1000000 && last_access <= time(0));
  }

  mmc_iterate_close(it);
}

int ForkTests(mmap_cache * cache, key_list * kl) {
#ifndef WIN32
  int pid, j, k, kid, kids[20], nkids = 0, status;
  struct timeval timeout = { 0, 1000 };

  for (j = 0; j < 8; j++) {
    if (!(pid = fork())) {
      RandSeed();
      RepeatMixTests(cache, 0.4, kl);
      exit(0);
    }
    kids[nkids++] = pid;
    select(0, 0, 0, 0, &timeout);
  }

  do {
    kid = waitpid(-1, &status, 0);
    for (j = 0, k = 0; j < nkids; j++) {
      if (kids[j] != kid) { k++; }
      kids[j] = kids[k];
    }
    nkids--;
  } while (kid > 0 && nkids);

  return 0;
#else
#endif
}


int main(int argc, char ** argv) {
  int res;
  key_list * kl;
  mmap_cache * cache;

  cache = mmc_new();
  mmc_set_param(cache, "init_file", "1");
  res = mmc_init(cache);

  kl = kl_new();

  BasicTests(cache);
  LinearTests(cache);

  mmc_close(cache);

  cache = mmc_new();
  mmc_set_param(cache, "init_file", "1");
  res = mmc_init(cache);

  RepeatMixTests(cache, 0.0, kl);
  RepeatMixTests(cache, 0.5, kl);
  RepeatMixTests(cache, 0.8, kl);

  IteratorTests(cache);

  ForkTests(cache, kl); 

  kl_free(kl);
  mmc_close(cache);

  cache = mmc_new();
  mmc_set_param(cache, "init_file", "1");
  mmc_set_param(cache, "page_size", "8192");
  res = mmc_init(cache);

  kl = kl_new();

  BasicTests(cache);
  RepeatMixTests(cache, 0.0, kl);
  RepeatMixTests(cache, 0.5, kl);
  RepeatMixTests(cache, 0.8, kl);

  ForkTests(cache, kl); 

  kl_free(kl);
  mmc_close(cache);

  return 0;
}

