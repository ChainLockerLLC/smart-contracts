// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/ChainLockerFactory.sol";

/// @notice foundry framework testing of ChainLockerFactory.sol
/** @dev test using mainnet fork in order to test SanctionsOracle, example commands:
 *** forge test -vvvv --fork-url https://eth.llamarpc.com
 *** forge test -vvvv --fork-url https://eth-mainnet.gateway.pokt.network/v1/5f3453978e354ab992c4da79
 *** or see https://ethereumnodes.com/ for alternatives */

/// @notice test contract for ChainLockerFactory using Foundry
contract ChainLockerFactoryTest is Test {
    ChainLockerFactory internal factoryTest;

    // internal in inherited contract so copied here
    ISanctionsOracle internal constant sanctionCheck =
        ISanctionsOracle(0x40C57923924B5c5c5455c48D93317139ADDaC8fb);

    // testing basic functionalities: refund, no valueCondition, identified buyer
    function setUp() public {
        factoryTest = new ChainLockerFactory();
    }

    function testConstructor() public {
        assertGt(factoryTest.feeDenominator(), 0, "feeDenominator not > 0");
        assertEq(
            factoryTest.receiver(),
            payable(address(this)),
            "receiver address mismatch"
        );
    }

    // test EthLocker deployment
    function testDeployEthLocker(
        address payable _buyer,
        address payable _seller,
        address _deployer,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        int224 _maxValue,
        int224 _minValue,
        uint8 _valueCondition
    ) public payable {
        // assume a valueCondition that is 1, 2, or 3 because the function requires the enum param (cannot submit > 3)
        vm.assume(_valueCondition < 4 && _valueCondition > 0);
        vm.startPrank(_deployer);
        // condition checks in ChainLockerFactory.deployChainlocker() and EthLocker's constructor
        if (
            sanctionCheck.isSanctioned(_deployer) ||
            _deposit > _totalAmount ||
            _totalAmount == 0 ||
            _expirationTime <= block.timestamp ||
            (_valueCondition == 3 && _minValue > _maxValue)
        ) vm.expectRevert();
        factoryTest.deployChainLocker(
            true,
            false,
            ChainLockerFactory.ValueCondition(_valueCondition),
            _maxValue,
            _minValue,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer,
            address(0),
            address(0)
        );
    }

    // test TokenLocker deployment
    function testDeployTokenLocker(
        address payable _buyer,
        address payable _seller,
        address _deployer,
        address _tokenContract,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        int224 _maxValue,
        int224 _minValue,
        uint8 _valueCondition
    ) public payable {
        // assume a valueCondition that is 1, 2, or 3 because the function requires the enum param (cannot submit > 3)
        vm.assume(_valueCondition < 4 && _valueCondition > 0);
        // mirror staticcall condition in TokenLocker constructor that '_tokenContract' is at least partially ERC-20 compliant by checking if both totalSupply and balanceOf functions exist
        (bool successTotalSupply, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("totalSupply()")
        );

        (bool successBalanceOf, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );

        vm.startPrank(_deployer);
        // condition checks in ChainLockerFactory.deployChainlocker() and TokenLocker's constructor
        if (
            sanctionCheck.isSanctioned(_deployer) ||
            _deposit > _totalAmount ||
            _totalAmount == 0 ||
            _expirationTime <= block.timestamp ||
            (_valueCondition == 3 && _minValue > _maxValue) ||
            (!successTotalSupply || !successBalanceOf)
        ) vm.expectRevert();
        factoryTest.deployChainLocker(
            true,
            false,
            ChainLockerFactory.ValueCondition(_valueCondition),
            _maxValue,
            _minValue,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract,
            address(0)
        );
    }

    function testUpdateReceiver(
        address payable _addr,
        address payable _addr2
    ) public {
        bool _reverted;
        // address(this) is calling the test contract so it should be the receiver for the call not to revert
        if (address(this) != factoryTest.receiver()) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.updateReceiver(_addr);
        vm.startPrank(_addr2);
        if (_addr != _addr2) vm.expectRevert();
        factoryTest.acceptReceiverRole();
        vm.stopPrank();
        vm.startPrank(_addr);
        factoryTest.acceptReceiverRole();
        if (!_reverted)
            assertEq(
                factoryTest.receiver(),
                _addr,
                "receiver address did not update"
            );
    }

    function testUpdateFee(
        address payable _caller,
        bool _feeSwitch,
        uint256 _newFeeDenominator,
        uint256 _newMinimumFee
    ) public {
        vm.startPrank(_caller);
        bool _updated;
        if (_caller != factoryTest.receiver() || _newFeeDenominator == 0)
            vm.expectRevert();
        else _updated = true;
        factoryTest.updateFee(_feeSwitch, _newFeeDenominator, _newMinimumFee);

        if (_updated) {
            assertEq(
                factoryTest.feeDenominator(),
                _newFeeDenominator,
                "feeDenominator did not update"
            );
            assertEq(
                factoryTest.minimumFee(),
                _newMinimumFee,
                "minimumFee did not update"
            );
            if (_feeSwitch)
                assertTrue(factoryTest.feeSwitch(), "feeSwitch did not update");
        }
    }
}
