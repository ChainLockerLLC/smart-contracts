// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/EthLocker.sol";

/// @dev foundry framework testing of EthLocker.sol

/// @notice test contract for EthLocker using Foundry
contract EthLockerTest is Test {
    EthLocker internal escrowTest;
    EthLocker internal openEscrowTest;
    EthLocker internal conditionEscrowTest;

    //assigned and used in 'testConditionExecute'
    int224 internal value;

    address payable internal buyer = payable(address(111111));
    address payable internal seller = payable(address(222222));
    address escrowTestAddr;
    uint256 internal deployTime;
    uint256 internal deposit = 1e14;
    uint256 internal totalAmount = 1e16;
    uint256 internal expirationTime = 5e15;

    // testing basic functionalities: refund, no valueCondition, identified buyer
    function setUp() public {
        escrowTest = new EthLocker(
            true,
            false,
            0,
            0,
            0,
            deposit,
            totalAmount,
            expirationTime,
            seller,
            buyer,
            address(0)
        );
        escrowTestAddr = address(escrowTest);
        deployTime = block.timestamp;
        vm.deal(address(this), totalAmount);
    }

    function testConstructor() public {
        assertEq(
            escrowTest.expirationTime(),
            expirationTime,
            "Expiry time mismatch"
        );
    }

    function testUpdateSeller(address payable _addr) public {
        vm.startPrank(escrowTest.seller());
        if (escrowTest.isExpired()) vm.expectRevert();

        escrowTest.updateSeller(_addr);
        assertEq(escrowTest.seller(), _addr, "seller address did not update");
    }

    function testUpdateBuyer(address payable _addr) public {
        vm.startPrank(escrowTest.buyer());
        bool _reverted;
        uint256 _amtDeposited = escrowTest.amountDeposited(buyer);
        if (escrowTest.isExpired()) {
            _reverted = true;
            vm.expectRevert();
        }

        escrowTest.updateBuyer(_addr);
        if (!_reverted) {
            assertEq(escrowTest.buyer(), _addr, "buyer address did not update");
            assertEq(
                escrowTest.amountDeposited(_addr),
                _amtDeposited,
                "amountDeposited mapping did not update"
            );
        }
    }

    function testReceive(uint256 _amount) public payable {
        uint256 _preBalance = escrowTest.amountDeposited(address(this));
        bool _success;
        //receive() will only be invoked if _amount > 0
        vm.assume(_amount > 0);
        vm.deal(address(this), _amount);

        if (
            _amount > totalAmount ||
            escrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        (_success, ) = escrowTestAddr.call{value: _amount}("");
        if (
            _amount > escrowTest.deposit() &&
            _amount <= escrowTest.totalAmount() &&
            _success
        )
            assertTrue(
                escrowTest.deposited(),
                "deposited variable did not update"
            );
        if (escrowTest.openOffer()) {
            assertTrue(
                escrowTest.buyer() == payable(msg.sender),
                "buyer variable did not update"
            );
        }
        if (_success && _amount <= escrowTest.totalAmount())
            assertGt(
                escrowTest.amountDeposited(address(this)),
                _preBalance,
                "amountDeposited mapping did not update"
            );
    }

    function testReadyToClose(address _caller) external {
        // if caller isn't seller or buyer and the sellerApproved and buyerApproved bools haven't already been changed, any other address
        // calling this function should do nothing and the bools should not update
        if (
            _caller != escrowTest.seller() &&
            _caller != escrowTest.buyer() &&
            !escrowTest.sellerApproved() &&
            !escrowTest.buyerApproved()
        ) {
            vm.startPrank(_caller);
            escrowTest.readyToExecute();
            assertTrue(!escrowTest.sellerApproved());
            assertTrue(!escrowTest.buyerApproved());
            vm.stopPrank();
        }

        //ensure seller and buyer can update their approved booleans
        vm.startPrank(escrowTest.seller());
        escrowTest.readyToExecute();
        assertTrue(escrowTest.sellerApproved());
        vm.stopPrank();
        vm.startPrank(escrowTest.buyer());
        escrowTest.readyToExecute();
        assertTrue(escrowTest.buyerApproved());
        vm.stopPrank();
    }

    // fuzz test for different timestamps
    function testCheckIfExpired(uint256 timestamp) external {
        // assume 'totalAmount' is in escrow
        vm.deal(escrowTestAddr, escrowTest.totalAmount());

        uint256 _preBuyerAmtWithdrawable = escrowTest.amountWithdrawable(buyer);
        uint256 _preSellerAmtWithdrawable = escrowTest.amountWithdrawable(
            seller
        );
        bool _preDeposited = escrowTest.deposited();
        vm.warp(timestamp);
        escrowTest.checkIfExpired();
        // ensure, if timestamp is past expiration time and thus escrow is expired, boolean is updated and totalAmount is credited to buyer
        // else, isExpired() should be false and amountWithdrawable mappings should be unchanged
        if (escrowTest.expirationTime() <= timestamp) {
            assertTrue(escrowTest.isExpired());
            if (escrowTest.refundable())
                assertGt(
                    escrowTest.amountWithdrawable(buyer),
                    _preBuyerAmtWithdrawable,
                    "buyer's amountWithdrawable should have been increased by refunded amount"
                );
            else if (!escrowTest.refundable() && _preDeposited) {
                uint256 _remainder = escrowTestAddr.balance -
                    escrowTest.deposit();
                assertEq(
                    escrowTest.amountWithdrawable(seller) -
                        _preSellerAmtWithdrawable,
                    escrowTest.deposit(),
                    "seller's amountWithdrawable should have been increased by non-refundable 'deposit'"
                );
                if (_remainder > 0)
                    assertEq(
                        escrowTest.amountWithdrawable(buyer),
                        _preBuyerAmtWithdrawable + _remainder,
                        "buyer's amountWithdrawable should have been increased by the the remainder (amount over 'deposit')"
                    );
            }
            assertEq(
                escrowTest.amountDeposited(escrowTest.buyer()),
                0,
                "buyer's amountDeposited was not deleted"
            );
        } else {
            assertTrue(!escrowTest.isExpired());
            assertEq(
                escrowTest.amountWithdrawable(seller),
                _preSellerAmtWithdrawable,
                "seller's amountWithdrawable should be unchanged"
            );
            assertEq(
                escrowTest.amountWithdrawable(buyer),
                _preBuyerAmtWithdrawable,
                "buyer's amountWithdrawable should be unchanged"
            );
        }
    }

    function testRejectDepositor(
        address payable _depositor,
        uint256 _deposit
    ) external {
        // '_deposit' must be less than 'totalAmount', and '_deposit' must be greater than 1e4 wei
        vm.assume(_deposit <= totalAmount && _deposit > 1e4);
        // deploy openOffer version of EthLocker with no valueCondition
        openEscrowTest = new EthLocker(
            true,
            true,
            0,
            0,
            0,
            _deposit,
            totalAmount,
            expirationTime,
            seller,
            buyer,
            address(0)
        );
        address payable _newContract = payable(address(openEscrowTest));
        bool _reverted;
        vm.assume(_newContract != _depositor);
        // give the '_deposit' amount to the '_depositor' so they can accept the open offer
        vm.deal(_depositor, _deposit);
        vm.startPrank(_depositor);
        if (
            _deposit + _newContract.balance > totalAmount ||
            (openEscrowTest.openOffer() && _deposit < totalAmount)
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        (bool _success, ) = _newContract.call{value: _deposit}("");

        bool _wasDeposited = openEscrowTest.deposited();
        uint256 _amountWithdrawableBefore = openEscrowTest.amountWithdrawable(
            _depositor
        );
        vm.stopPrank();
        // reject depositor as 'seller'
        vm.startPrank(seller);
        if (
            openEscrowTest.amountDeposited(_depositor) < _deposit || !_success
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        openEscrowTest.rejectDepositor(_depositor);
        if (!_reverted || _newContract != address(this)) {
            if (_wasDeposited && _success && _depositor != address(0)) {
                assertEq(
                    address(0),
                    openEscrowTest.buyer(),
                    "buyer address did not delete"
                );
                assertGt(
                    openEscrowTest.amountWithdrawable(_depositor),
                    _amountWithdrawableBefore,
                    "_depositor's amountWithdrawable did not update"
                );
            }
            assertEq(
                0,
                openEscrowTest.amountDeposited(_depositor),
                "amountDeposited did not delete"
            );
        }
    }

    function testWithdraw(address _caller) external {
        uint256 _preBalance = escrowTestAddr.balance;
        uint256 _preAmtWithdrawable = escrowTest.amountWithdrawable(_caller);
        bool _reverted;

        vm.startPrank(_caller);
        if (escrowTest.amountWithdrawable(_caller) == 0) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.withdraw();

        assertEq(
            escrowTest.amountWithdrawable(_caller),
            0,
            "not all of 'amountWithdrawable' was withdrawn"
        );
        if (!_reverted) {
            assertGt(
                _preBalance,
                escrowTestAddr.balance,
                "balance of escrowTest not affected"
            );
            assertGt(
                _preAmtWithdrawable,
                escrowTest.amountWithdrawable(_caller),
                "amountWithdrawable not affected"
            );
        }
    }

    function testExecute() external {
        // if 'totalAmount' isn't in escrow, expect revert
        if (escrowTestAddr.balance != escrowTest.totalAmount()) {
            vm.expectRevert();
            escrowTest.execute();
        }

        // deal 'totalAmount' in escrow, otherwise sellerApproval() will be false (which is captured by this test anyway)
        vm.deal(escrowTestAddr, escrowTest.totalAmount());

        uint256 _preBalance = escrowTestAddr.balance;
        uint256 _preSellerBalance = escrowTest.seller().balance;
        bool _approved;

        if (!escrowTest.sellerApproved() || !escrowTest.buyerApproved())
            vm.expectRevert();
        else _approved = true;

        escrowTest.execute();

        // both approval booleans should have been deleted regardless of whether the escrow expired
        assertTrue(!escrowTest.sellerApproved());
        assertTrue(!escrowTest.buyerApproved());

        // if both seller and buyer approved closing before the execute() call and expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !escrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(
                _preBalance,
                escrowTestAddr.balance,
                "escrow's balance should have been reduced by 'totalAmount'"
            );
            assertGt(
                escrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should have been increased by 'totalAmount'"
            );
            assertEq(
                escrowTestAddr.balance,
                0,
                "escrow balance should be zero"
            );
        } else if (escrowTest.isExpired()) {
            //balances should not change if expired
            assertEq(
                _preBalance,
                escrowTestAddr.balance,
                "escrow's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertEq(
                escrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
        }
    }

    /// @dev test execution with a valueCondition
    function testConditionedExecute(
        int224 _fuzzedValue,
        int224 _maxValue,
        int224 _minValue,
        uint8 _valueCondition
    ) external {
        // a valueCondition that is 1, 2, or 3 and that minValue is not greater than maxValue
        vm.assume(
            _valueCondition < 4 && _valueCondition > 0 && _minValue <= _maxValue
        );

        /// feed 'address(this)' as the dataFeedProxy to return the fuzzed value
        conditionEscrowTest = new EthLocker(
            true,
            true,
            _valueCondition,
            _maxValue,
            _minValue,
            deposit,
            totalAmount,
            expirationTime,
            seller,
            buyer,
            address(this)
        );
        value = _fuzzedValue;
        vm.prank(buyer);
        conditionEscrowTest.readyToExecute();
        vm.stopPrank();
        vm.prank(seller);
        conditionEscrowTest.readyToExecute();
        vm.stopPrank();
        vm.deal(address(conditionEscrowTest), totalAmount);

        uint256 _preSellerBalance = conditionEscrowTest.seller().balance;
        bool _approved;

        if (
            !conditionEscrowTest.sellerApproved() ||
            !conditionEscrowTest.buyerApproved() ||
            (_valueCondition == 1 && _fuzzedValue > _maxValue) ||
            (_valueCondition == 2 && _fuzzedValue < _minValue) ||
            (_valueCondition == 3 &&
                (_fuzzedValue > _maxValue || _fuzzedValue < _minValue))
        ) vm.expectRevert();
        else _approved = true;

        conditionEscrowTest.execute();

        // if both seller and buyer approved closing before the execute() call and expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !conditionEscrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(
                totalAmount,
                address(conditionEscrowTest).balance,
                "escrow's balance should have been reduced by 'totalAmount'"
            );
            assertGt(
                conditionEscrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should have been increased by 'totalAmount'"
            );
            assertEq(
                address(conditionEscrowTest).balance,
                0,
                "escrow balance should be zero"
            );
        } else if (conditionEscrowTest.isExpired()) {
            //balances should not change if expired
            assertEq(
                totalAmount,
                address(conditionEscrowTest).balance,
                "escrow's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertEq(
                conditionEscrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
        }
    }

    function read() public view returns (int224, uint256) {
        return (value, block.timestamp);
    }
}
