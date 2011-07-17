#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
#include "mmap_cache.h"

#define FC_UTF8VAL (1<<31)
#define FC_UTF8KEY (1<<30)
#define FC_UNDEF (1<<29)

#define FC_ENTRY \
    mmap_cache * cache; \
    if (!SvROK(obj)) { \
      croak("Object not reference"); \
      XSRETURN_UNDEF; \
    } \
    obj = SvRV(obj); \
    if (!SvIOKp(obj)) { \
      croak("Object not initiliased correctly"); \
      XSRETURN_UNDEF; \
    } \
    cache = INT2PTR(mmap_cache *, SvIV(obj) ); \
    if (!cache) { \
      croak("Object not created correctly"); \
      XSRETURN_UNDEF; \
    }


MODULE = Cache::FastMmap		PACKAGE = Cache::FastMmap
PROTOTYPES: ENABLE

SV *
fc_new()
  INIT:
    mmap_cache * cache;
    SV * obj_pnt, * obj;
  CODE:
    cache = mmc_new();

    /* Create integer which is pointer to cache object */
    obj_pnt = newSViv(PTR2IV(cache));

    /* Create reference to integer value. This will be the object */
    obj = newRV_noinc((SV *)obj_pnt);

    RETVAL = obj;
  OUTPUT:
    RETVAL

NO_OUTPUT int
fc_set_param(obj, param, val)
    SV * obj;
    char * param;
    char * val;
  INIT:
    FC_ENTRY

  CODE:
    RETVAL = mmc_set_param(cache, param, val);
  POSTCALL:
    if (RETVAL != 0) {
      croak("%s", mmc_error(cache));
    }

NO_OUTPUT int
fc_init(obj)
    SV * obj;
  INIT:
    FC_ENTRY

  CODE:
    RETVAL = mmc_init(cache);
  POSTCALL:
    if (RETVAL != 0) {
      croak("%s", mmc_error(cache));
    }


void
fc_close(obj)
    SV * obj
  INIT:
    FC_ENTRY

  CODE:
    mmc_close(cache);
    sv_setiv(obj, 0);


void
fc_hash(obj, key);
    SV * obj;
    SV * key;
  INIT:
    int key_len;
    void * key_ptr;
    MU32 hash_page, hash_slot;
    STRLEN pl_key_len;

    FC_ENTRY

  PPCODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Hash key to get page and slot */
    mmc_hash(cache, key_ptr, key_len, &hash_page, &hash_slot);

    XPUSHs(sv_2mortal(newSViv((IV)hash_page)));
    XPUSHs(sv_2mortal(newSViv((IV)hash_slot)));


NO_OUTPUT int
fc_lock(obj, page);
    SV * obj;
    UV page;
  INIT:
    FC_ENTRY

  CODE:
    RETVAL = mmc_lock(cache, (MU32)page);
  POSTCALL:
    if (RETVAL != 0) {
      croak("%s", mmc_error(cache));
    }


NO_OUTPUT int
fc_unlock(obj);
    SV * obj;
  INIT:
    FC_ENTRY

  CODE:
    RETVAL = mmc_unlock(cache);
  POSTCALL:
    if (RETVAL != 0) {
      croak("%s", mmc_error(cache));
    }

int
fc_is_locked(obj)
    SV * obj;
  INIT:
    FC_ENTRY

  CODE:
    /* Write value to cache */
    RETVAL = mmc_is_locked(cache);

  OUTPUT:
    RETVAL


void
fc_read(obj, hash_slot, key)
    SV * obj;
    U32  hash_slot;
    SV * key;
  INIT:
    int key_len, val_len, found;
    void * key_ptr, * val_ptr;
    MU32 flags = 0;
    STRLEN pl_key_len;
    SV * val;

    FC_ENTRY

  PPCODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Get value data pointer */
    found = mmc_read(cache, (MU32)hash_slot, key_ptr, key_len, &val_ptr, &val_len, &flags);

    /* If not found, use undef */
    if (found == -1) {
      val = &PL_sv_undef;
    } else {

      /* Cached an undef value? */
      if (flags & FC_UNDEF) {
        val = &PL_sv_undef;

      } else {

        /* Create PERL SV */
        val = sv_2mortal(newSVpvn((const char *)val_ptr, val_len));

        /* Make UTF8 if stored from UTF8 */
        if (flags & FC_UTF8VAL) {
          SvUTF8_on(val);
        }

      }
      flags = flags & ~(FC_UTF8KEY | FC_UTF8VAL | FC_UNDEF);
    }

    XPUSHs(val);
    XPUSHs(sv_2mortal(newSViv((IV)flags)));
    XPUSHs(sv_2mortal(newSViv((IV)!found)));


int
fc_write(obj, hash_slot, key, val, expire_seconds, in_flags)
    SV * obj;
    U32  hash_slot;
    SV * key;
    SV * val;
    U32 expire_seconds;
    U32 in_flags;
  INIT:
    int key_len, val_len;
    void * key_ptr, * val_ptr;
    STRLEN pl_key_len, pl_val_len;

    FC_ENTRY

  CODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Check for storing undef, and store empty string with undef flag set */
    if (!SvOK(val)) {
      in_flags |= FC_UNDEF;

      val_ptr = "";
      val_len = 0;

    } else {

      /* Get key length, data pointer */
      val_ptr = (void *)SvPV(val, pl_val_len);
      val_len = (int)pl_val_len;

      /* Set UTF8-ness flag of stored value */
      if (SvUTF8(val)) {
        in_flags |= FC_UTF8VAL;
      }
      if (SvUTF8(key)) {
        in_flags |= FC_UTF8KEY;
      }
    }

    /* Write value to cache */
    RETVAL = mmc_write(cache, (MU32)hash_slot, key_ptr, key_len, val_ptr, val_len, (MU32)expire_seconds, (MU32)in_flags);

  OUTPUT:
    RETVAL

int
fc_delete(obj, hash_slot, key)
    SV * obj;
    U32  hash_slot;
    SV * key;
  INIT:
    MU32 out_flags;
    int key_len, did_delete;
    void * key_ptr;
    STRLEN pl_key_len;

    FC_ENTRY

  PPCODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Write value to cache */
    did_delete = mmc_delete(cache, (MU32)hash_slot, key_ptr, key_len, &out_flags);

    XPUSHs(sv_2mortal(newSViv((IV)did_delete)));
    XPUSHs(sv_2mortal(newSViv((IV)out_flags)));


void
fc_get_page_details(obj)
    SV * obj;
  INIT:
    MU32 nreads = 0, nreadhits = 0;

    FC_ENTRY

  PPCODE:
    mmc_get_page_details(cache, &nreads, &nreadhits);

    XPUSHs(sv_2mortal(newSViv((IV)nreads)));
    XPUSHs(sv_2mortal(newSViv((IV)nreadhits)));


NO_OUTPUT void
fc_reset_page_details(obj)
    SV * obj;
  INIT:
    MU32 nreads = 0, nreadhits = 0;

    FC_ENTRY

  CODE:
    mmc_reset_page_details(cache);



void
fc_expunge(obj, mode, wb, len)
    SV * obj;
    int mode;
    int wb;
    int len;
  INIT:
    MU32 new_num_slots = 0, ** to_expunge = 0;
    int num_expunge, item;

    void * key_ptr, * val_ptr;
    int key_len, val_len;
    MU32 last_access, expire_time, flags;

    FC_ENTRY

  PPCODE:

    num_expunge = mmc_calc_expunge(cache, mode, len, &new_num_slots, &to_expunge);
    if (to_expunge) {

      /* Want list of expunged keys/values? */
      if (wb) {

        for (item = 0; item < num_expunge; item++) {
          mmc_get_details(cache, to_expunge[item],
            &key_ptr, &key_len, &val_ptr, &val_len,
            &last_access, &expire_time, &flags);

          {
          HV * ih = (HV *)sv_2mortal((SV *)newHV());

          SV * key = newSVpvn((const char *)key_ptr, key_len);
          SV * val;

          if (flags & FC_UTF8KEY) {
            SvUTF8_on(key);
            flags ^= FC_UTF8KEY;
          }

          if (flags & FC_UNDEF) {
            val = newSV(0);
            flags ^= FC_UNDEF;
          } else {
            val = newSVpvn((const char *)val_ptr, val_len);
            if (flags & FC_UTF8VAL) {
              SvUTF8_on(val);
              flags ^= FC_UTF8VAL;
            }
          }

          /* Store in hash ref */
          hv_store(ih, "key", 3, key, 0); 
          hv_store(ih, "value", 5, val, 0);
          hv_store(ih, "last_access", 11, newSViv((IV)last_access), 0);
          hv_store(ih, "expire_time", 11, newSViv((IV)expire_time), 0);
          hv_store(ih, "flags", 5, newSViv((IV)flags), 0); 

          /* Create reference to hash */
          XPUSHs(sv_2mortal(newRV((SV *)ih)));
          }
        }
      }

      mmc_do_expunge(cache, num_expunge, new_num_slots, to_expunge);
    }




void
fc_get_keys(obj, mode)
    SV * obj;
    int mode;
  INIT:
    mmap_cache_it * it;
    MU32 * entry_ptr;
    void * key_ptr, * val_ptr;
    int key_len, val_len;
    MU32 last_access, expire_time, flags;

    FC_ENTRY

  PPCODE:

    it = mmc_iterate_new(cache);

    /* Iterate over all items */
    while (entry_ptr = mmc_iterate_next(it)) {
      SV *  key;
      mmc_get_details(cache, entry_ptr,
        &key_ptr, &key_len, &val_ptr, &val_len,
        &last_access, &expire_time, &flags);

      /* Create key SV, and set UTF8'ness if needed */
      key = newSVpvn((const char *)key_ptr, key_len);
      if (flags & FC_UTF8KEY) {
        SvUTF8_on(key);
        flags ^= FC_UTF8KEY;
      }

      /* Mode 0 is just list of keys */
      if (mode == 0) {
        XPUSHs(sv_2mortal(key));

      /* Mode 1/2 is list of hash-refs */
      } else if (mode == 1 || mode == 2) {
        HV * ih = (HV *)sv_2mortal((SV *)newHV());

        /* These things by default */
        hv_store(ih, "key", 3, key, 0); 
        hv_store(ih, "last_access", 11, newSViv((IV)last_access), 0);
        hv_store(ih, "expire_time", 11, newSViv((IV)expire_time), 0);
        hv_store(ih, "flags", 5, newSViv((IV)flags), 0); 

        /* Add value to hash-ref if mode 2 */
        if (mode == 2) {
          SV * val;
          if (flags & FC_UNDEF) {
            val = newSV(0);
            flags ^= FC_UNDEF;
          } else {
            val = newSVpvn((const char *)val_ptr, val_len);
            if (flags & FC_UTF8VAL) {
              SvUTF8_on(val);
              flags ^= FC_UTF8VAL;
            }
          }
          hv_store(ih, "value", 5, val, 0);
        }

        /* Create reference to hash */
        XPUSHs(sv_2mortal(newRV((SV *)ih)));
      }
    }

    mmc_iterate_close(it);





SV *
fc_get(obj, key)
    SV * obj;
    SV * key;
  INIT:
    int key_len, val_len, found;
    void * key_ptr, * val_ptr;
    MU32 hash_page, hash_slot, flags;
    STRLEN pl_key_len;
    SV * val;

    FC_ENTRY

  CODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Hash key to get page and slot */
    mmc_hash(cache, key_ptr, key_len, &hash_page, &hash_slot);

    /* Get and lock the page */
    mmc_lock(cache, hash_page);

    /* Get value data pointer */
    found = mmc_read(cache, hash_slot, key_ptr, key_len, &val_ptr, &val_len, &flags);

    /* If not found, use undef */
    if (found == -1) {
      val = &PL_sv_undef;
    } else {

      /* Create PERL SV */
      val = newSVpvn((const char *)val_ptr, val_len);
    }

    mmc_unlock(cache);
    RETVAL = val;
  OUTPUT:
    RETVAL


void
fc_set(obj, key, val)
    SV * obj;
    SV * key;
    SV * val;
  INIT:
    int key_len, val_len, found;
    void * key_ptr, * val_ptr;
    MU32 hash_page, hash_slot, flags = 0;
    STRLEN pl_key_len, pl_val_len;

    FC_ENTRY

  CODE:

    /* Get key length, data pointer */
    key_ptr = (void *)SvPV(key, pl_key_len);
    key_len = (int)pl_key_len;

    /* Get key length, data pointer */
    val_ptr = (void *)SvPV(val, pl_val_len);
    val_len = (int)pl_val_len;

    /* Hash key to get page and slot */
    mmc_hash(cache, key_ptr, key_len, &hash_page, &hash_slot);

    /* Get and lock the page */
    mmc_lock(cache, hash_page);

    /* Get value data pointer */
    mmc_write(cache, hash_slot, key_ptr, key_len, val_ptr, val_len, -1, flags);

    mmc_unlock(cache);


NO_OUTPUT void
fc_dump_page(obj);
    SV * obj;
  INIT:
    FC_ENTRY

  CODE:
    _mmc_dump_page(cache);


