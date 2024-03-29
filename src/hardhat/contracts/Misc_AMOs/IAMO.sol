// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

interface IAMO {
    function btcBalances() external view returns (uint256 brax_val_e18, uint256 collat_val_e18);
}
