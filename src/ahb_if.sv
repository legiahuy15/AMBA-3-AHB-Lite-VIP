//==============================================================================
// File        : ahb_if.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite interface with address & data chanel.
//               Includes clocking blocks for master driver, slave driver,
//               and monitor to avoid race conditions.
//               Signal widths use parameters from ahb_types.sv.
//==============================================================================
