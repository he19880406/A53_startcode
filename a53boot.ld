OUTPUT_FORMAT( "elf64-littleaarch64")
OUTPUT_ARCH(aarch64)
ENTRY(start64)

MEMORY{
	 RAM (rwx): ORIGIN = 0x00000000, LENGTH = 0x00200000
}

SECTIONS
{
	. = 0x00000000;
	. = ALIGN(4);
	.text : 
	{
		*startup.o (.text)
		*(.text)
	} > RAM
	
	. = ALIGN(4);
	 .rodata : { *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.rodata*))) } > RAM
	 
	 .data : { 
        __data_start = .;
        *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.data*)))
        __data_end = .;
        } > RAM
        
         . = ALIGN(4);
        .bss : { 
        __bss_start = .;
        *(.bss) 
        __bss_end  = .;
        } > RAM
        
        . = ALIGN(64);
        ARM_LIB_STACK = .;        
        . += (4*0x4000);
        
        . = ALIGN(64);
        EL3_STACK = . ;
        . += (4*0x1000);
        
        . = ALIGN(64);
        ARM_LIB_HEAP = . ;
        . += 0xA0000;
        
	    . = ALIGN(4096);
        TTB0_L1 = . ;
        . += 0x1000;
        
        . = ALIGN(4096);
        TTB0_L2_RAM = .;
        . += 0x1000;
        
        . = ALIGN(4096);
        TTB0_L2_PRIVATE = . ;
        . += 0x1000;
        
        . = ALIGN(4096);
        TTB0_L2_PERIPH = . ;
        . += 0x1000;
        
        . = ALIGN(4096);
        TTB0_L2_PERIPH1 = . ;
        . += 0x1000;
        
        TOP_OF_RAM = . ;      
        
}