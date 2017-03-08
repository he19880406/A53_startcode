/*
 * ARMv8 - Main
 *
 * Copyright (c) 2011-2014 ARM Ltd.  All rights reserved.
 *
 */

//#include <stdlib.h>
//#include <stdio.h>

#include "v8_aarch64.h"

// compile-time control for the number of CPUs in the cluster
static const int nCPUs = 4;


void MainApp(void)
{
   
}

/*
 * void main(void)
 *    the application start point for the primary CPU - bring up the
 *    secondary CPUs and then call MainApp
 *
 *  Inputs
 *    <none>
 *
 *  Returns
 *    subroutine does not return
 */
int main(void)
{
    EnableCachesEL1();        // Enable the caches
    while(1){};
}
