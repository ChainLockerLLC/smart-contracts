// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/Receipt.sol";

/// @dev foundry framework testing of Receipt.sol

/// basic ERC20 for testing 'decimals()'
contract ERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        name = "Test Token";
        symbol = "TEST";
        decimals = 18;
        _mint(msg.sender, 1e18);
    }

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
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

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

/// @notice test contract for Receipt using Foundry
contract ReceiptTest is Test {
    Receipt public receiptTest;
    ERC20 public testToken;

    // copy internal variable from Receipt.sol
    uint256 internal constant ONE_DAY = 86400;

    // variables to mock an IProxy call
    uint256 timestamp;
    int224 value;

    address internal deployer;
    address tokenAddr;

    function setUp() public {
        receiptTest = new Receipt();
        deployer = address(this);
    }

    function testConstructor() public {
        assertEq(deployer, receiptTest.admin(), "initial admin != deployer");
    }

    function testUpdateAdmin(address _addr) public {
        bool _reverted;
        // address(this) is calling the test contract so it should be the admin for the call not to revert
        if (address(this) != receiptTest.admin()) {
            _reverted = true;
            vm.expectRevert();
        }
        receiptTest.updateAdmin(_addr);
        if (!_reverted)
            assertEq(
                receiptTest.admin(),
                _addr,
                "admin address did not update"
            );
    }

    function testUpdateProxy(address _token, address _proxy) public {
        bool _reverted;
        // address(this) is calling the test contract so it should be the admin for the call not to revert
        if (address(this) != receiptTest.admin()) {
            _reverted = true;
            vm.expectRevert();
        }
        receiptTest.updateProxy(_token, _proxy);
        if (!_reverted)
            assertEq(
                receiptTest.tokenToProxy(_token),
                _proxy,
                "tokenToProxy mapping did not update"
            );
    }

    function testDeployTokenAndUpdateProxy() public {
        testToken = new ERC20();
        address _token = address(testToken);
        receiptTest.updateProxy(_token, address(this));
        assertEq(
            receiptTest.tokenToProxy(_token),
            address(this),
            "tokenToProxy mapping did not update"
        );
    }

    function testPrintReceipt(
        uint256 _tokenAmount,
        uint256 _timestamp,
        int224 _value
    ) public {
        // deploy a new 18 decimal ERC20 for testing
        testToken = new ERC20();
        address _token = address(testToken);
        value = _value;
        timestamp = _timestamp;

        // update the proxy mapping for the new '_token' to address(this) so the test read() function is called
        receiptTest.updateProxy(_token, address(this));
        if (
            _tokenAmount == 0 ||
            _tokenAmount > type(uint32).max ||
            _timestamp > block.timestamp ||
            _timestamp + ONE_DAY < block.timestamp ||
            _value < int224(0)
        ) vm.expectRevert();

        (uint256 _testId, uint256 _usdValue) = receiptTest.printReceipt(
            _token,
            _tokenAmount
        );

        if (_testId != 0)
            assertGt(_testId, 0, "test's 'paymentId' did not increment");
        assertEq(
            _usdValue,
            receiptTest.paymentIdToUsdValue(_testId),
            "paymentIdToUsdValue mapping did not update"
        );
    }

    function read() public view returns (int224, uint256) {
        return (value, timestamp);
    }
}
