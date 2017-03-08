// ------------------------------------------------------------
// ARMv8-A Vector tables
//
// Copyright (c) 2014 ARM Ltd.  All rights reserved.
// ------------------------------------------------------------

    .section  EL1VECTORS
    .text
    .align 11

    .global el1_vectors
    .global el2_vectors
    .global el3_vectors
    .global c0sync1

.equ ESR_EL1_EC_SHIFT, (26)
.equ ESR_EL1_EC_DABT_EL1,	(0x25)
.equ ESR_EL1_EC_SYS64,	(0x18)
.equ ESR_EL1_EC_SP_ALIGN,	(0x26)
.equ ESR_EL1_EC_PC_ALIGN,	(0x22)
.equ ESR_EL1_EC_UNKNOWN,	(0x00)
.equ ESR_EL1_EC_BREAKPT_EL1,	(0x31)

.macro	kernel_entry, el
	sub	sp, sp, #0x30	// room for LR, SP, SPSR, ELR
	stp x28, x29, [sp, #-16]!
	stp x26, x27, [sp, #-16]!
	stp x24, x25, [sp, #-16]!
	stp x22, x23, [sp, #-16]!
	stp x20, x21, [sp, #-16]!
	stp x18, x19, [sp, #-16]!
	stp x16, x17, [sp, #-16]!
	stp x14, x15, [sp, #-16]!
	stp x12, x13, [sp, #-16]!
	stp x10, x11, [sp, #-16]!
	stp x8, x9, [sp, #-16]!
	stp x6, x7, [sp, #-16]!
	stp x4, x5, [sp, #-16]!
	stp x2, x3, [sp, #-16]!
	stp x0, x1, [sp, #-16]!

	.if	\el == 0
	mrs	x21, sp_el0
	.else
	add	x21, sp, #0x120
	.endif
	mrs	x22, elr_el1
	mrs	x23, spsr_el1
	stp	x30, x21, [sp, #240]
	stp	x22, x23, [sp, #256]
	.endm

.macro	kernel_exit, el, ret = 0
	ldp	x21, x22, [sp, #256]		// load ELR, SPSR
	.if	\el == 0
	ldr	x23, [sp, #248]		// load return stack pointer
	.endif
	.if	\ret
	ldr	x1, [sp, #8]			// preserve x0 (syscall return)
	add	sp, sp, #0x10
	.else
	//pop	x0, x1
	ldp x0, x1, [sp], #16
	.endif
	//pop	x2, x3				// load the rest of the registers
	ldp x2, x3, [sp], #16
	//pop	x4, x5
	//pop	x6, x7
	//pop	x8, x9
	ldp x4, x5, [sp], #16
	ldp x6, x7, [sp], #16
	ldp x8, x9, [sp], #16
	msr	elr_el1, x21			// set up the return data
	msr	spsr_el1, x22
	.if	\el == 0
	msr	sp_el0, x23
	.endif

	ldp x10, x11, [sp], #16
	ldp x12, x13, [sp], #16
	ldp x14, x15, [sp], #16
	ldp x16, x17, [sp], #16
	ldp x18, x19, [sp], #16
	ldp x20, x21, [sp], #16
	ldp x22, x23, [sp], #16
	ldp x24, x25, [sp], #16
	ldp x26, x27, [sp], #16
	ldp x28, x29, [sp], #16
	ldr	x30, [sp], #48	// load LR and restore SP
	eret					// return to kernel
	.endm

//
// Current EL with SP0
//
el1_vectors:
c0sync1: B c0sync1

    .balign 0x80
c0irq1: B c0irq1

    .balign 0x80
c0fiq1: B c0fiq1

    .balign 0x80
c0serr1: B c0serr1

//
// Current EL with SPx
//
    .balign 0x80
cxsync1: B cxsync1_proc

    .balign 0x80
cxirq1: B cxirq1_proc

    .balign 0x80
cxfiq1: B cxfiq1_proc

    .balign 0x80
cxserr1: B cxserr1

//
// Lower EL using AArch64
//
    .balign 0x80
l64sync1:
    B   l64sync1

    .balign 0x80
l64irq1:
    B   l64irq1

    .balign 0x80
l64fiq1:
    B   l64fiq1

    .balign 0x80
l64serr1:
    B   l64serr1

//
// Lower EL using AArch32
//
    .balign 0x80
l32sync1:
    B   l32sync1

    .balign 0x80
l32irq1:
    B   l32irq1

    .balign 0x80
l32fiq1:
    B   l32fiq1

    .balign 0x80
l32serr1:
    B   l32serr1


cxsync1_proc:
	kernel_entry 1
	mrs	x1, esr_el1			// read the syndrome register
	lsr	x24, x1, #ESR_EL1_EC_SHIFT	// exception class
	cmp	x24, #ESR_EL1_EC_DABT_EL1	// data abort in EL1
	b.eq	el1_da
	cmp	x24, #ESR_EL1_EC_SYS64		// configurable trap
	b.eq	el1_undef
	cmp	x24, #ESR_EL1_EC_SP_ALIGN	// stack alignment exception
	b.eq	el1_sp_pc
	cmp	x24, #ESR_EL1_EC_PC_ALIGN	// pc alignment exception
	b.eq	el1_sp_pc
	cmp	x24, #ESR_EL1_EC_UNKNOWN	// unknown exception in EL1
	b.eq	el1_undef
	cmp	x24, #ESR_EL1_EC_BREAKPT_EL1	// debug exception in EL1
	b.ge	el1_dbg
	b	el1_inv

el1_da:
	mrs x0, far_el1
	kernel_exit 1
el1_undef:
el1_sp_pc:
el1_dbg:
el1_inv:
	kernel_exit 1

cxirq1_proc:
	kernel_entry 1
	kernel_exit 1

cxfiq1_proc:
	kernel_entry 1
	kernel_exit 1


//----------------------------------------------------------------

    .section  EL2VECTORS
    .text
    .align 11

//
// Current EL with SP0
//
el2_vectors:
c0sync2: B c0sync2

    .balign 0x80
c0irq2: B c0irq2

    .balign 0x80
c0fiq2: B c0fiq2

    .balign 0x80
c0serr2: B c0serr2

//
// Current EL with SPx
//
    .balign 0x80
cxsync2: B cxsync2

    .balign 0x80
cxirq2: B cxirq2

    .balign 0x80
cxfiq2: B cxfiq2

    .balign 0x80
cxserr2: B cxserr2

//
// Lower EL using AArch64
//
    .balign 0x80
l64sync2:
    B   l64sync2

    .balign 0x80
l64irq2:
    B   l64irq2

    .balign 0x80
l64fiq2:
    B   l64fiq2

    .balign 0x80
l64serr2:
    B   l64serr2

//
// Lower EL using AArch32
//
    .balign 0x80
l32sync2:
    B   l32sync2

    .balign 0x80
l32irq2:
    B   l32irq2

    .balign 0x80
l32fiq2:
    B   l32fiq2

    .balign 0x80
l32serr2:
    B   l32serr2

//----------------------------------------------------------------

    .section  EL3VECTORS
    .text
    .align 11

//
// Current EL with SP0
//
el3_vectors:
c0sync3: B c0sync3

    .balign 0x80
c0irq3: B c0irq3

    .balign 0x80
c0fiq3: B c0fiq3

    .balign 0x80
c0serr3: B c0serr3

//
// Current EL with SPx
//
    .balign 0x80
cxsync3: B cxsync3

    .balign 0x80
cxirq3: B cxirq3

    .balign 0x80
cxfiq3: B cxfiq3

    .balign 0x80
cxserr3: B cxserr3

//
// Lower EL using AArch64
//
    .balign 0x80
l64sync3:
    B   l64sync3

    .balign 0x80
l64irq3:
    B   l64irq3

    .balign 0x80
l64fiq3:
    B   l64fiq3

    .balign 0x80
l64serr3:
    B   l64serr3

//
// Lower EL using AArch32
//
    .balign 0x80
l32sync3:
    B   l32sync3

    .balign 0x80
l32irq3:
    B   l32irq3

    .balign 0x80
l32fiq3:
    B   l32fiq3

    .balign 0x80
l32serr3:
    B   l32serr3
