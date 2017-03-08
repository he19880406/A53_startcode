// ------------------------------------------------------------
// ARMv8-A AArch64 - Common helper functions
//
// Copyright (c) 2012-2014 ARM Ltd.  All rights reserved.
// ------------------------------------------------------------

    .section  v8_helper_funcs
    .text

        .include "armclang/v8_system.s"

    .global EnableCachesEL1
////      .global  DisableCachesEL1
    .global InvalidateUDCaches
    .global GetMIDR
    .global GetMPIDR
    .global GetCPUID

// ------------------------------------------------------------

//
// void EnableCachesEL1(void)
//
//    enable Instruction and Data caches
//
    .type EnableCachesEL1, @function
EnableCachesEL1:

    mrs x0, SCTLR_EL1
    orr x0, x0, #SCTLR_ELx_I
    orr x0, x0, #SCTLR_ELx_C
    msr     SCTLR_EL1, x0

    isb
    ret


// ------------------------------------------------------------
  .ifdef TESTING
    .type DisableCachesEL1, @function
DisableCachesEL1:

    mrs x0, SCTLR_EL1
    and x0, x0, #~SCTLR_ELx_I
    and x0, x0, #~SCTLR_ELx_C
    msr     SCTLR_EL1, x0

    isb
    ret
  .endif


// ------------------------------------------------------------

    .type InvalidateUDCaches, @function
InvalidateUDCaches:

    //
    // don't invalidate until all prior accesses have
    // been observed
    //
    dmb ish

    //
    // get CLIDR_EL1.LoC into w2, and give up if there aren't any
    //
    mrs     x0, CLIDR_EL1
    ubfx    w2, w0, #24, #3
    cbz w2, invalidateUDCaches_end

    mov w1, #0                  // w1 = level iterator

flush_level:
    add  w3, w1, w1, lsl #1     // w3 = w1 * 3 (right-shift for cache type)
    lsr  w3, w0, w3             // w3 = w0 >> w3
    ubfx w3, w3, #0, #3         // w3 = cache type of this level
    cmp  w3, #2                 // No cache at this level?
    b.lt next_level

    lsl w4, w1, #1
    msr CSSELR_EL1, x4          // Select current cache level in CSSELR
    isb                         // ISB required to reflect new CSIDR
    mrs x4, CSSELR_EL1          // w4 = CSIDR

    ubfx w3, w4, #0, #3
    add  w3, w3, #2             // w3 = log2(line size)
    ubfx w5, w4, #13, #15
    ubfx w4, w4, #3, #10        // w4 = Way number
    clz  w6, w4                 // w6 = 32 - log2(number of ways)

flush_set:
    mov  w8, w4                 // w8 = Way number
flush_way:
    lsl  w7, w1, #1             // Fill level field
    lsl  w9, w5, w3
    orr  w7, w7, w9             // Fill index field
    lsl  w9, w8, w6
    orr  w7, w7, w9             // Fill way field
    dc   cisw, x7               // Invalidate by set/way to point of coherency
    subs w8, w8, #1             // Decrement way
    b.ge flush_way
    subs w5, w5, #1             // Decrement set
    b.ge flush_set

next_level:
    add  w1, w1, #1             // Next level
    cmp  w2, w1
    b.gt flush_level

    //
    // one last barrier, to ensure these operations by set/way are
    // observed before any subsequent explicit memory access
    //
invalidateUDCaches_end:
    dmb ish
    ret
     

// ------------------------------------------------------------

//
// ID Register functions
//

    .type GetMIDR, @function
GetMIDR:

    mrs x0, MIDR_EL1
    ret


    .type GetMPIDR, @function
GetMPIDR:

    mrs x0, MPIDR_EL1
    ret


    .type GetCPUID, @function
GetCPUID:

    mrs x0, MPIDR_EL1

    //
    // we're working with x0, even though this subroutine is
    // supposed to return a 32-bit value but that's OK, since
    // if MPIDR_EL1_AFF0_WIDTH was >32, the function would be
    // declared as returning a 64-bit value
    //
    ubfx    x0, x0, #MPIDR_EL1_AFF0_LSB, #MPIDR_EL1_AFF_WIDTH
    ret
