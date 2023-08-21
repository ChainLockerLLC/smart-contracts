// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/TokenLocker.sol";

/// @dev foundry framework testing of TokenLocker.sol including a mock ERC20Permit

/// @notice Modern, minimalist, and gas-optimized ERC20 implementation for testing
/// @author Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/tokens/ERC20/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 Logic
    /// -----------------------------------------------------------------------

    function approve(
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

/// @notice ERC20 + EIP-2612 implementation, including EIP712 logic.
/** @dev Solbase ERC20Permit implementation (https://github.com/Sol-DAO/solbase/blob/main/src/tokens/ERC20/extensions/ERC20Permit.sol)
 ** plus Solbase EIP712 implementation (https://github.com/Sol-DAO/solbase/blob/main/src/utils/EIP712.sol)*/
abstract contract ERC20Permit is ERC20 {
    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 internal constant DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    bytes32 internal hashedDomainName;
    bytes32 internal hashedDomainVersion;
    bytes32 internal initialDomainSeparator;
    uint256 internal initialChainId;

    /// @dev `keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) public nonces;

    error PermitExpired();
    error InvalidSigner();

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _version,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        hashedDomainName = keccak256(bytes(_name));
        hashedDomainVersion = keccak256(bytes(_version));
        initialDomainSeparator = _computeDomainSeparator();
        initialChainId = block.chainid;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) revert PermitExpired();

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                _computeDigest(
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            spender,
                            value,
                            nonces[owner]++,
                            deadline
                        )
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0)) revert InvalidSigner();
            if (recoveredAddress != owner) revert InvalidSigner();
            allowance[recoveredAddress][spender] = value;
        }
    }

    function domainSeparator() public view virtual returns (bytes32) {
        return
            block.chainid == initialChainId
                ? initialDomainSeparator
                : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    hashedDomainName,
                    hashedDomainVersion,
                    block.chainid,
                    address(this)
                )
            );
    }

    function _computeDigest(
        bytes32 hashStruct
    ) internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator(), hashStruct)
            );
    }
}

/// @notice ERC20 token contract
/// @dev not burnable or mintable; ERC20Permit implemented
contract TestToken is ERC20Permit {
    /// -----------------------------------------------------------------------
    /// ERC20 data
    /// -----------------------------------------------------------------------
    string public constant TESTTOKEN_NAME = "Test Token";
    string public constant TESTTOKEN_SYMBOL = "TEST";
    string public constant TESTTOKEN_VERSION = "1";
    uint8 public constant TESTTOKEN_DECIMALS = 18;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        address _user
    )
        ERC20Permit(
            TESTTOKEN_NAME,
            TESTTOKEN_SYMBOL,
            TESTTOKEN_VERSION,
            TESTTOKEN_DECIMALS
        )
    {
        _mint(_user, 1e24);
    }

    //allow anyone to mint the token for testing
    function mintToken(address to, uint256 amt) public {
        _mint(to, amt);
    }
}

/// @dev to test EIP-712 operations
contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    // mockToken.domainSeparator()
    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMITTYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMITTYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(
        Permit memory _permit
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }
}

/// @notice test contract for TokenLocker using Foundry
contract TokenLockerTest is Test {
    TestToken internal testToken;
    TokenLocker internal escrowTest;
    TokenLocker internal openEscrowTest;
    TokenLocker internal conditionEscrowTest;
    SigUtils internal sigUtils;

    address internal buyer;
    address internal seller = address(222222);
    address escrowTestAddr;
    address testTokenAddr;
    // for testConditionExecute, returned in mock read() function
    int224 internal value;
    uint256 internal deployTime;
    uint256 internal deposit = 1e14;
    uint256 internal totalAmount = 1e16;
    uint256 internal expirationTime = 5e15;
    uint256 internal ownerPrivateKey;

    // testing basic functionalities: refund, no valueCondition, identified buyer, known ERC20 compliance
    function setUp() public {
        testToken = new TestToken(buyer);
        testTokenAddr = address(testToken);
        // initialize EIP712 variables
        sigUtils = new SigUtils(testToken.domainSeparator());
        ownerPrivateKey = 0xA11CE;
        buyer = vm.addr(ownerPrivateKey);
        escrowTest = new TokenLocker(
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
            testTokenAddr,
            address(0)
        );
        escrowTestAddr = address(escrowTest);
        deployTime = block.timestamp;
        //give buyer tokens
        testToken.mintToken(buyer, totalAmount);
    }

    function testConstructor() public {
        assertEq(
            escrowTest.expirationTime(),
            expirationTime,
            "Expiry time mismatch"
        );
    }

    function testUpdateSeller(address _addr) public {
        vm.startPrank(escrowTest.seller());
        if (escrowTest.isExpired()) vm.expectRevert();

        escrowTest.updateSeller(_addr);
        assertEq(escrowTest.seller(), _addr, "seller address did not update");
    }

    function testUpdateBuyer(address _addr) public {
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

    function testDepositTokensWithPermit(
        uint256 _amount,
        uint256 _deadline
    ) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: buyer,
            spender: escrowTestAddr,
            value: _amount,
            nonce: 0,
            deadline: _deadline
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        // check amountDeposited mapping pre-call
        uint256 _beforeAmountDeposited = escrowTest.amountDeposited(buyer);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.prank(buyer);
        if (
            _amount > totalAmount ||
            (escrowTest.openOffer() && _amount < totalAmount) ||
            escrowTest.expirationTime() <= block.timestamp ||
            _deadline < block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokensWithPermit(
            permit.owner,
            permit.value,
            permit.deadline,
            v,
            r,
            s
        );
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (permit.value > 0 && !_reverted) {
            uint256 _afterAmountDeposited = escrowTest.amountDeposited(buyer);
            assertGt(
                _afterAmountDeposited,
                _beforeAmountDeposited,
                "amountDeposited mapping did not update for owner"
            );
            assertGt(
                _afterBalance,
                _beforeBalance,
                "balanceOf escrow did not increase"
            );
            if (
                _amount > escrowTest.deposit() &&
                _amount <= escrowTest.totalAmount()
            )
                assertTrue(
                    escrowTest.deposited(),
                    "deposited variable did not update"
                );
            if (escrowTest.openOffer())
                assertTrue(
                    escrowTest.buyer() == msg.sender,
                    "buyer variable did not update"
                );
        }
    }

    function testDepositTokens(uint256 _amount) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount);

        uint256 _beforeAmountDeposited = escrowTest.amountDeposited(buyer);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.startPrank(buyer);
        testToken.approve(escrowTestAddr, _amount);
        if (
            _amount + testToken.balanceOf(address(this)) > totalAmount ||
            (escrowTest.openOffer() && _amount < totalAmount) ||
            escrowTest.expirationTime() <= block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokens(_amount);
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (_amount > 0 && !_reverted) {
            uint256 _afterAmountDeposited = escrowTest.amountDeposited(buyer);
            assertGt(
                _afterAmountDeposited,
                _beforeAmountDeposited,
                "amountDeposited mapping did not update for owner"
            );
            assertGt(
                _afterBalance,
                _beforeBalance,
                "balanceOf escrow did not increase"
            );
            if (
                _amount > escrowTest.deposit() &&
                _amount <= escrowTest.totalAmount()
            )
                assertTrue(
                    escrowTest.deposited(),
                    "deposited variable did not update"
                );
            if (escrowTest.openOffer())
                assertTrue(
                    escrowTest.buyer() == payable(msg.sender),
                    "buyer variable did not update"
                );
        }
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
        testToken.mintToken(address(escrowTest), escrowTest.totalAmount());

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
                uint256 _remainder = address(escrowTest).balance -
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
        address _depositor,
        uint256 _deposit
    ) external {
        // '_deposit' must be greater than 1e4 wei and not greater than 'totalAmount'
        vm.assume(_deposit > 1e4 && _deposit <= totalAmount);
        // deploy openOffer version of TokenLocker with no valueCondition
        openEscrowTest = new TokenLocker(
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
            testTokenAddr,
            address(0)
        );
        address _newContract = address(openEscrowTest);
        bool _reverted;

        // give the '_deposit' amount to the '_depositor' so they can accept the open offer by calling 'depositTokens'
        testToken.mintToken(_depositor, _deposit);
        vm.startPrank(_depositor);
        testToken.approve(_newContract, _deposit);
        if (
            _deposit + testToken.balanceOf(_newContract) > totalAmount ||
            (openEscrowTest.openOffer() && _deposit < totalAmount)
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        openEscrowTest.depositTokens(_deposit);

        bool _wasDeposited = openEscrowTest.deposited();
        uint256 _amountWithdrawableBefore = openEscrowTest.amountWithdrawable(
            _depositor
        );
        vm.stopPrank();
        // reject depositor as 'seller'
        vm.startPrank(seller);
        if (openEscrowTest.amountDeposited(_depositor) < _deposit) {
            _reverted = true;
            vm.expectRevert();
        }
        openEscrowTest.rejectDepositor(_depositor);
        if (!_reverted || _newContract != address(this)) {
            if (_wasDeposited && _depositor != address(0)) {
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
        uint256 _preBalance = testToken.balanceOf(escrowTestAddr);
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
                testToken.balanceOf(escrowTestAddr),
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
        if (testToken.balanceOf(escrowTestAddr) != escrowTest.totalAmount()) {
            vm.expectRevert();
            escrowTest.execute();
        }

        // deal 'totalAmount' in escrow, otherwise sellerApproval() will be false (which is captured by this test anyway)
        testToken.mintToken(escrowTestAddr, escrowTest.totalAmount());

        uint256 _preBalance = testToken.balanceOf(escrowTestAddr);
        uint256 _preBuyerBalance = testToken.balanceOf(buyer);
        uint256 _preSellerBalance = testToken.balanceOf(seller);
        bool _approved;

        if (!escrowTest.sellerApproved() || !escrowTest.buyerApproved())
            vm.expectRevert();
        else _approved = true;

        escrowTest.execute();

        // both approval booleans should have been deleted regardless of whether the escrow expired
        assertTrue(!escrowTest.sellerApproved());
        assertTrue(!escrowTest.buyerApproved());

        // if both seller and buyer approved closing before the execute() call, proceed
        if (_approved) {
            // if the expiration time has been met or surpassed, check the same things as in 'testCheckIfExpired()' and that both approval booleans were deleted
            // else, seller should have received totalAmount
            if (escrowTest.isExpired()) {
                assertGt(
                    _preBalance,
                    testToken.balanceOf(escrowTestAddr),
                    "escrow's balance should have been reduced by 'totalAmount'"
                );
                assertGt(
                    testToken.balanceOf(escrowTestAddr),
                    _preBuyerBalance,
                    "buyer's balance should have been increased by 'totalAmount'"
                );
            } else {
                assertGt(
                    _preBalance,
                    testToken.balanceOf(escrowTestAddr),
                    "escrow's balance should have been reduced by 'totalAmount'"
                );
                assertGt(
                    testToken.balanceOf(seller),
                    _preSellerBalance,
                    "seller's balance should have been increased by 'totalAmount'"
                );
                assertEq(
                    testToken.balanceOf(escrowTestAddr),
                    0,
                    "escrow balance should be zero"
                );
            }
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
        vm.assume(_valueCondition < 4 && _valueCondition > 0);
        vm.assume(_minValue <= _maxValue);

        value = _fuzzedValue;

        /// feed 'address(this)' as the dataFeedProxy to return the fuzzed value from read()
        conditionEscrowTest = new TokenLocker(
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
            testTokenAddr,
            address(this)
        );
        address conditionEscrowTestAddr = address(conditionEscrowTest);
        vm.prank(buyer);
        conditionEscrowTest.readyToExecute();
        vm.stopPrank();
        vm.prank(seller);
        conditionEscrowTest.readyToExecute();
        vm.stopPrank();
        testToken.mintToken(conditionEscrowTestAddr, totalAmount);

        uint256 _preBalance = testToken.balanceOf(conditionEscrowTestAddr);
        uint256 _preBuyerBalance = testToken.balanceOf(buyer);
        uint256 _preSellerBalance = testToken.balanceOf(seller);
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

        // if both seller and buyer approved closing before the execute() call, proceed
        if (_approved) {
            // if the expiration time has been met or surpassed, check the same things as in 'testCheckIfExpired()' and that both approval booleans were deleted
            // else, seller should have received totalAmount
            if (conditionEscrowTest.isExpired()) {
                assertGt(
                    _preBalance,
                    testToken.balanceOf(conditionEscrowTestAddr),
                    "escrow's balance should have been reduced by 'totalAmount'"
                );
                assertGt(
                    testToken.balanceOf(buyer),
                    _preBuyerBalance,
                    "buyer's balance should have been increased by 'totalAmount'"
                );
            } else {
                assertGt(
                    _preBalance,
                    testToken.balanceOf(conditionEscrowTestAddr),
                    "escrow's balance should have been reduced by 'totalAmount'"
                );
                assertGt(
                    testToken.balanceOf(seller),
                    _preSellerBalance,
                    "seller's balance should have been increased by 'totalAmount'"
                );
            }
        }
    }

    function read() public view returns (int224, uint256) {
        return (value, block.timestamp);
    }
}
