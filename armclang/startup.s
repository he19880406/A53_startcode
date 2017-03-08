// ------------------------------------------------------------
// ARMv8 Startup Code
//
// Basic Vectors, MMU and caches initialization
//
// Copyright (c) 2014 ARM Ltd.  All rights reserved.
// ------------------------------------------------------------

    //.section  StartUp
    .text
    .align 8

    .global el1_vectors
    .global el2_vectors
    .global el3_vectors

    .global InvalidateUDCaches
    .global ZeroBlock

    .global SetIrqGroup
    .global SetBlockGroup
    .global SetSPIGroup
    .global SendSGI
    .global EnableIRQ
    .global TestIRQ
    .global EnableGICD
    .global EnableGICC
    .global SetIRQPriority
    .global SetPriorityMask
    .global ClearSGI

    .global __main
    .global MainApp
    
    .global TTB0_L1

    .include "armclang/v8_mmu.s"
    .include "armclang/v8_system.s"

// ------------------------------------------------------------

    .global start64
    .type start64, @function
start64:
    //
    // program the VBARs
    //
    ldr x3, lit_el3_vectors
    msr VBAR_EL3, x3

    //
    // lower exception levels are in the non-secure world, with no access
    // back to EL2 or EL3, and are AArch64 capable
    //
    // EL3 switch EL1S
    mov w3, #(SCR_EL3_RW  | SCR_EL3_SMD)
    msr SCR_EL3, x3

    //
    // no traps or VM modifications from the Hypervisor, EL1 is AArch64
    //
    mov x2, HCR_EL2_RW
    msr HCR_EL2, x2

    //
    // VMID is still significant, even when virtualisation is not
    // being used, so ensure VTTBR_EL2 is properly initialised
    //
    msr VTTBR_EL2, xzr

    //
    // neither EL3 nor EL2 trap floating point or accesses to CPACR
    //
    msr CPTR_EL3, xzr
    msr CPTR_EL2, xzr

    //
    // set SCTLRs for lower ELs to safe values
    //
    // note that setting SCTLR_EL2 is not strictly
    // needed, since we're never in EL2
    //
    msr SCTLR_EL1, xzr
    msr SCTLR_EL2, xzr

    //
    // That's the last of the control settings for now
    //
    // Note: no ISB after all these changes, as registers won't be
    // accessed until after an exception return, which is itself a
    // context synchronisation event
    //

    //
    // setup some EL3 stack space, ready for calling some subroutines, below
    // stack space allocation is CPU-specific, so get CPU number, 
    // and keep it in x19 (defined by the AAPCS as callee-saved),
    // so we can re-use the number later
    //
    // 2^12 bytes per CPU for the EL3 stacks
    //
    ldr x0, Image__EL3_STACKS__ZI__Limit
    mrs x19, MPIDR_EL1
    ubfx x19, x19, MPIDR_EL1_AFF0_LSB, MPIDR_EL1_AFF_WIDTH
    sub x0, x0, x19, lsl #12
    mov sp, x0

    //
    // there's more GIC setup to do, but only for the primary CPU
    //
    cbnz x19, drop_to_el1

    //
    // Set up EL1 entry point and "dummy" exception return information,
    // then perform exception return to enter EL1
    //
    .global drop_to_el1
drop_to_el1:
    adr x1, el1_entry_aarch64
    msr ELR_EL3, x1
    mov x1, #(AARCH64_SPSR_EL1h | AARCH64_SPSR_F  | AARCH64_SPSR_I  | AARCH64_SPSR_A)
    msr SPSR_EL3, x1
    eret

         

// ------------------------------------------------------------
// EL1 - Common start-up code
// ------------------------------------------------------------

    .global el1_entry_aarch64
    .type el1_entry_aarch64, @function
el1_entry_aarch64:
	//
    // program the VBARs
    //
    ldr x1, lit_el1_vectors
    msr VBAR_EL1, x1

    //
    // Now we're in EL1, setup the application stack
    // the scatter file allocates 2^14 bytes per app stack
    //
    ldr x0, Image__ARM_LIB_STACK__ZI__Limit
    sub x0, x0, x19, lsl #14
    mov sp, x0

    //
    // Invalidate caches and TLBs for all stage 1
    // translations used at EL1
    //
    bl  InvalidateUDCaches
    tlbi VMALLE1

    //
    // Set the Base address
    //
    // The CPUs share one set of translation tables that are
    // generated by CPU0 at run-time
    //
    // TTBR1_EL1 is not used in this example
    //
    ldr x1, Image__TTB0_L1__ZI__Base
    msr TTBR0_EL1, x1

    //
    // Set up memory attributes
    //
    // These equate to:
    //
    // 0 -> 0b01000100 = Normal, Inner/Outer Non-Cacheable
    // 1 -> 0b11111111 = Normal, Inner/Outer WriteBack Read/Write Allocate
    // 2 -> 0b00000100 = Device-nGnRE
    //
    mov  x1, #0x000000000000FF44
    movk x1, #4, LSL #16    // equiv to: movk x1, #0x0000000000040000
    msr MAIR_EL1, x1

    //
    // Set up TCR_EL1
    //
    // We're using only TTBR0 (EPD1 = 1), and the page table entries:
    //  - are using an 8-bit ASID from TTBR0
    //  - have a 4K granularity (TG0 = 0b00)
    //  - are outer-shareable (SH0 = 0b10)
    //  - are using Inner & Outer WBWA Normal memory ([IO]RGN0 = 0b01)
    //  - map
    //      + 32 bits of VA space (T0SZ = 0x20)
    //      + into a 32-bit PA space (IPS = 0b000)
    //
    //     36   32   28   24   20   16   12    8    4    0
    //  -----+----+----+----+----+----+----+----+----+----+
    //       |    |    |OOII|    |    |    |00II|    |    |
    //    TT |    |    |RRRR|E T |   T|    |RRRR|E T |   T|
    //    BB | I I|TTSS|GGGG|P 1 |   1|TTSS|GGGG|P 0 |   0|
    //    IIA| P P|GGHH|NNNN|DAS |   S|GGHH|NNNN|D S |   S|
    //    10S| S-S|1111|1111|11Z-|---Z|0000|0000|0 Z-|---Z|
    //
    //    000 0000 0000 0000 1000 0000 0010 0101 0010 0000
    //
    //                    0x    8    0    2    5    2    0
    //
    // Note: the ISB is needed to ensure the changes to system
    //       context are before the write of SCTLR_EL1.M to enable
    //       the MMU. It is likely on a "real" implementation that
    //       this setup would "work" without an ISB due to the
    //       amount of code that gets executed before enabling the
    //       MMU, but that would not be architecturally correct.
    //
    ldr x1, lit_803520
    msr TCR_EL1, x1
    isb

    //
    // x19 already contains the CPU number, so branch to secondary
    // code if we're not on CPU0
    //
    cbnz x19, el1_secondary

    //
    // Fall through to primary code
    //
         

//
// ------------------------------------------------------------
//
// EL1 - primary CPU init code
//
// This code is run on CPU0, while the other CPUs are in the
// holding pen
//

    .global el1_primary
    .type el1_primary, @function
el1_primary:

    //
    // We're now on the primary processor in the NS world, so turn on
    // the banked GIC distributor enable, ready for individual CPU
    // enables later
    //
    bl  EnableGICD

    //
    // Generate TTBR0 L1
    //
    // at 4KB granularity, 32-bit VA space, table lookup starts at
    // L1, with 1GB regions
    //
    // we are going to create entries pointing to L2 tables for a
    // couple of these 1GB regions, the first of which is the
    // RAM on the VE board model - get the table addresses and
    // start by emptying out the L1 page tables (4 entries at L1
    // for a 4K granularity)
    //
    // x21 = address of L1 tables
    //
    ldr x21, Image__TTB0_L1__ZI__Base
    mov x0, x21
    mov x1, #(4 << 3)
    bl  ZeroBlock

    //
    // time to start mapping the RAM regions - clear out the
    // L2 tables and point to them from the L1 tables
    //
    // x0 = address of L2 tables
    //
    ldr x0, Image__TTB0_L2_RAM__ZI__Base
    mov x1, #(512 << 3)
    bl  ZeroBlock

    //
    // Get the start address of RAM (the EXEC region) into x4
    // and calculate the offset into the L1 table (1GB per region,
    // max 4GB)
    //
	ldr x4, Image__L2_RAM__ZI_Base
    ldr x5, Image__TOP_OF_RAM__ZI__Base
    ubfx x2, x4, #30, #2

    orr x1, x0, #TT_S1_ATTR_TABLE
    str x1, [x21, x2, lsl #3]

    //
    // we've already used the RAM start address in x4 - we now need to get this 
    // in terms of an offset into the L2 page tables, where each entry covers 2MB
    // x5 is the last known Execute region in RAM, convert this to an offset too,
    // being careful to round up, then calculate the number of entries to write
    //
    ubfx x2, x4, #21, #9
    sub  x3, x5, #1
    ubfx x3, x3, #21, #9
    add  x3, x3, #1
    sub  x3, x3, x2

    //
    // set x1 to the required page table attributes, then orr
    // in the start address (modulo 2MB)
    //
    // L2 tables in our configuration cover 2MB per entry - map
    // memory as Shared, Normal WBWA (MAIR[1]) with a flat
    // VA->PA translation
    //
    // Amlogic memory config:
    // 0x000 ~ 0x001 2MB normal&cachable
    and x4, x4, 0xffffffffffe00000 // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | (1 << TT_S1_ATTR_MATTR_LSB) | TT_S1_ATTR_NS | TT_S1_ATTR_AP_RW_PL1 | TT_S1_ATTR_SH_INNER | TT_S1_ATTR_AF | TT_S1_ATTR_nG)
    orr x1, x1, x4

    //
    // factor the offset into the page table address and then write
    // the entries
    //
    add x0, x0, x2, lsl #3

loop1:
    subs x3, x3, #1
    str x1, [x0], #8
    add x1, x1, #0x200, LSL #12    // equiv to add x1, x1, #(1 << 21)  // 2MB per entry
    bne loop1

	// amlogic memory config:
	// 0x002~0x003 2MB normal&non-cachable, XN=1
	and x4, x1, 0xfffffffffffff000
    mov x1, #(TT_S1_ATTR_BLOCK | (0 << TT_S1_ATTR_MATTR_LSB) | TT_S1_ATTR_NS | TT_S1_ATTR_AP_RW_PL1 | TT_S1_ATTR_AF | TT_S1_ATTR_nG)
	// XN:PXN = b11
	movk x1, #0x60, lsl #48
	orr x1, x1, x4
	str x1, [x0], #8

    //
    // now mapping the Peripheral regions - clear out the
    // L2 tables and point to them from the L1 tables
    //
    // The assumption here is that all peripherals live within
    // a common 1GB region (i.e. that there's a single set of
    // L2 pages for all the peripherals). We only use a UART
    // and the GIC in this example, so the assumption is sound
    //
    // x0 = address of L2 tables
    //
    //ldr x0, Image__TTB0_L2_PERIPH__ZI__Base
    ldr x0, Image__TTB0_L2_PRIVATE__ZI__Base
    mov x1, #(512 << 3)
    bl  ZeroBlock

    //
    // get the PRIVATE_PERIPHERALS address into x4 and calculate
    // the offset into the L1 table
    //
    ldr x4, Image__PRIVATE_PERIPHERALS__ZI__Base
    ubfx x2, x4, #30, #2

    orr x1, x0, #TT_S1_ATTR_TABLE
    str x1, [x21, x2, lsl #3]

    //
    // there's only going to be a single 2MB region for PRIVATE_PERIPHERALS (in
    // x4) - get this in terms of an offset into the L2 page tables
    //
    ubfx x2, x4, #21, #9

	//Amlogic memory config:
	// 0x400~0x600   0x200MB normal&cachable, XN=1
    and x4, x4, 0xffffffffffe00000 // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | (1 << TT_S1_ATTR_MATTR_LSB) | TT_S1_ATTR_NS | TT_S1_ATTR_AP_RW_PL1 | TT_S1_ATTR_AF | TT_S1_ATTR_nG)
    // XN/PXN=1
    movk x1, #0x60, lsl #48
    orr x1, x1, x4

	add x0, x0, x2, lsl #3
	mov x3, 256
loop_l2_private:
	subs x3, x3, #1
	str x1, [x0], 8
	add x1, x1, #0x200, lsl #12
	bne loop_l2_private

   // the 3rd 1GB memory config
    // amlogic periphal range1:
    // 0x800~0x801 2MB device&XN=1
	ldr x0, Image__TTB0_L2_PERIPH__ZI__Base
	mov x1, #(512<<3)
	bl ZeroBlock

	ldr x4, Image__COMMON_PERIPHERALS__ZI__Base
	ubfx x2, x4, #30, #2

	orr x1, x0, #TT_S1_ATTR_TABLE
	str x1, [x21, x2, lsl #3]

	ubfx x2, x4, #21, #9
	and x4, x4, 0xffffffffffe00000 // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | (2 << TT_S1_ATTR_MATTR_LSB) | TT_S1_ATTR_NS | TT_S1_ATTR_AP_RW_PL1 | TT_S1_ATTR_AF | TT_S1_ATTR_nG)
    // XN/PXN=1
    movk x1, #0x60, lsl #48
    orr x1, x1, x4
    str x1, [x0, x2, lsl #3]

	// amlogic memory config
    // amlogic periph1: 0xc00~0xd00
    // 0xc00~0xd00 0x100MB device&XN=1
	ldr x0, Image__TTB0_L2_PERIPH1__ZI__Base
	mov x1, #(512<<3)
	bl ZeroBlock

	ldr x4, Image__PERIPHERALS1__ZI__Base
	ubfx x2, x4, #30, #2

	orr x1, x0, #TT_S1_ATTR_TABLE
	str x1, [x21, x2, lsl #3]

	ubfx x2, x4, #21, #9
	and x4, x4, 0xffffffffffe00000 // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | (2 << TT_S1_ATTR_MATTR_LSB) | TT_S1_ATTR_NS | TT_S1_ATTR_AP_RW_PL1 | TT_S1_ATTR_AF | TT_S1_ATTR_nG)
    // XN:PXN = b11
    movk x1, #0x60, lsl #48
    orr x1, x1, x4
   // str x1, [x0, x2, lsl #3]

	add x0, x0, x2, lsl #3
    mov x3, #128
loop_1:
	subs x3, x3, #1
	str x1, [x0], #8
	add x1, x1, #0x200, lsl #12
	bne loop_1

    //
    // issue a barrier to ensure all table entry writes are complete
    //
    dsb ish

    //
    // Enable the MMU
    //
    mrs x1, SCTLR_EL1
    orr x1, x1, SCTLR_ELx_M
    orr x1, x1, SCTLR_ELx_C
    orr x1, x1, SCTLR_ELx_I
    msr SCTLR_EL1, x1
    isb

 //#ifdef TESTING
 #if 1
    //
    // Test whether soft interrupts are working correctly, as we
    // want to use them for waking up the secondaries
    //
    // Try to send SGI13 to ourselves
    //
    mov w0, #13
    mov w1, #(2 << 1) // we're in NS world, so adjustment is needed
    bl  SetIRQPriority

    mov w0, #13
    bl  EnableIRQ

    mov w0, #(15 << 1)
    bl  SetPriorityMask

    bl  EnableGICC
    mov w0, #13
    mov w1, #2        // sgi_tlf_mask
    mov w2, #0
    mov w3, #0
    bl  SendSGI

loop0:
    mov w0, #13
    bl  TestIRQ
    cbz w0, loop0
  #endif
    //
    // Branch to C library init code
    //
    //B  __main
    b main

         

// ------------------------------------------------------------
// EL1 - secondary CPU init code
//
// This code is run on CPUs 1, 2, 3 etc....
// ------------------------------------------------------------

    .global el1_secondary
    .type el1_secondary, @function
el1_secondary:

    //
    // the primary CPU is going to use SGI 15 as a wakeup event
    // to let us know when it is OK to proceed, so prepare for
    // receiving that interrupt
    //
    // NS interrupt priorities run from 0 to 15, with 15 being
    // too low a priority to ever raise an interrupt, so let's
    // use 14
    //
    mov w0, #15
    mov w1, #(14 << 1) // we're in NS world, so adjustment is needed
    bl  SetIRQPriority

    mov w0, #15
    bl  EnableIRQ

    mov w0, #(15 << 1)
    bl  SetPriorityMask

    bl  EnableGICC

    //
    // wait for our interrupt to arrive
    //

loop_wfi:
    dsb SY      // Clear all pending data accesses
    wfi         // Go to sleep

    //
    // something woke us from our wait, was it the required interrupt?
    //
    mov w0, #15
    bl  TestIRQ
    cbz w0, loop_wfi

    //
    // it was - there's no need to actually take the interrupt,
    // so just clear it
    //
    mov w0, #15
    mov w1, #0        // IRQ was raised by the primary CPU
    bl  ClearSGI

    //
    // Enable MMU
    //
    mrs x1, SCTLR_EL1
    orr x1, x1, SCTLR_ELx_M
    orr x1, x1, SCTLR_ELx_C
    orr x1, x1, SCTLR_ELx_I
    msr SCTLR_EL1, x1
    isb

    //
    // Branch to thread start
    //
    B  MainApp


    // literal pools to provide equivalent of LDR=
  .align 3
lit_el1_vectors:
  .quad(el1_vectors)
lit_el2_vectors:
  .quad(el2_vectors)
lit_el3_vectors:
  .quad(el3_vectors)
lit_803520:
  .quad(0x0000000000803520)

Image__TTB0_L1__ZI__Base:
  .quad(TTB0_L1)
Image__TTB0_L2_RAM__ZI__Base:
  .quad(TTB0_L2_RAM)
Image__TTB0_L2_PRIVATE__ZI__Base:
   .quad(TTB0_L2_PRIVATE)
Image__TTB0_L2_PERIPH__ZI__Base:
  .quad(TTB0_L2_PERIPH)
Image__TTB0_L2_PERIPH1__ZI__Base:
  .quad(TTB0_L2_PERIPH1)

Image__L2_RAM__ZI_Base:
   .quad(0x00000000)
Image__TOP_OF_RAM__ZI__Base:
  .quad(0x00200000)
Image__PRIVATE_PERIPHERALS__ZI__Base:
  .quad(0x40000000)
Image__COMMON_PERIPHERALS__ZI__Base:
	.quad(0x80000000)
Image__PERIPHERALS1__ZI__Base:
	.quad(0xc0000000)

Image__ARM_LIB_STACK__ZI__Limit:
  .quad(ARM_LIB_STACK)
Image__EL3_STACKS__ZI__Limit:
  .quad(EL3_STACK)