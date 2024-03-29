// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.11;

import "./IBraxGaugeController.sol";

// https://github.com/swervefi/swerve/edit/master/packages/swerve-contracts/interfaces/IGaugeController.sol

interface IBraxGaugeControllerV2 is IBraxGaugeController {
    struct CorrectedPoint {
        uint256 bias;
        uint256 slope;
        uint256 lock_end;
    }

    function get_corrected_info(address) external view returns (CorrectedPoint memory);
}
