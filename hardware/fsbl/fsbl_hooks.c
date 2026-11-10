/* Copyright (c) 2012 - 2020 Xilinx, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 * Board-specific implementation of the standard Xilinx FSBL hooks.
 */
#include "fsbl.h"
#include "fsbl_hooks.h"
#include "xil_io.h"
#include "xuartps_hw.h"
#include "sleep.h"

#define BOARD_UART1_BASE 0xE0001000U
#define SLCR_UNLOCK_REG 0xF8000008U
#define SLCR_LOCK_REG   0xF8000004U
#define MIO48_REG       0xF80007C0U
#define MIO49_REG       0xF80007C4U

u32 FsblHookBeforeBitstreamDload(void)
{
    return XST_SUCCESS;
}

u32 FsblHookAfterBitstreamDload(void)
{
    return XST_SUCCESS;
}

u32 FsblHookBeforeHandoff(void)
{
    u32 control;

    /* UART1 is wired through PL EMIO, not the ZC702 MIO48/49 route. */
    Xil_Out32(SLCR_UNLOCK_REG, 0xDF0DU);
    Xil_Out32(MIO48_REG, 0x1601U);
    Xil_Out32(MIO49_REG, 0x1601U);
    Xil_Out32(SLCR_LOCK_REG, 0x767BU);

    /* Discard RX debris accumulated while the PL UART path was unavailable.
     * Preserve baud rate and TX state; U-Boot's normal abort window remains.
     */
    usleep(1000U);
    control = XUartPs_ReadReg(BOARD_UART1_BASE, XUARTPS_CR_OFFSET);
    control &= ~(XUARTPS_CR_RX_EN | XUARTPS_CR_RX_DIS |
                 XUARTPS_CR_RXRST | XUARTPS_CR_TXRST);
    XUartPs_WriteReg(BOARD_UART1_BASE, XUARTPS_CR_OFFSET,
                    control | XUARTPS_CR_RX_DIS | XUARTPS_CR_RXRST);
    XUartPs_WriteReg(BOARD_UART1_BASE, XUARTPS_ISR_OFFSET, XUARTPS_IXR_MASK);
    XUartPs_WriteReg(BOARD_UART1_BASE, XUARTPS_CR_OFFSET,
                    control | XUARTPS_CR_RX_EN);
    return XST_SUCCESS;
}

void FsblHookFallback(void)
{
    while (1) { }
}
