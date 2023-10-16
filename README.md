# ChainLocker Smart Contracts

_Please note that all code, files, forms, templates, or other materials provided or linked herein (the "Repo Contents") are provided by ChainLocker LLC strictly as-is under the MIT License; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of any of the Repo Contents or any smart contracts or other software deployed from these files._

_Any users, developers, or adapters of the Repo Contents or any deployments or instances thereof should proceed with caution and use at their own risk._

***

ChainLocker is a non-custodial, user-defined-and-deployed escrow deployment protocol. Each ChainLocker is a separate contract deployment, and is designed to only hold one type of asset per deployment. 

Deployers may choose to create an 'openOffer' ChainLocker that is open to any counterparty, a 'refundable' ChainLocker which enables the counterparty to withdraw their 'deposit' if there has been no successful execution before the 'expirationTime', a ChainLocker with execution contigent on an oracle-fed data condition known as a 'ValueCondition', and more.

The locked assets are programmatically released provided all deployer-defined conditions are met when <code>execute()</code> is called; if the necessary conditions are not met before the deployer-defined expiry, assets become withdrawable according to the deployer-defined deposit and refundability rules. 

***


## ChainLockerFactory.sol

Factory contract for ChainLocker deployments (TokenLocker or EthLocker) based upon the various parameters passed to <code>deployChainLocker()</code>. For deployments with a non-zero <code>ValueCondition</code>, the execution of the ChainLocker pre-expiry is reliant upon the accurate operation and security of the applicable <code>dataFeedProxy</code> contract (specifically its <code>read()</code> function) so users are advised to carefully verify and monitor such contract. The parameters for a ChainLocker deployment by calling <code>deployChainLocker()</code> are:

-	<code>_refundable</code>: Boolean of whether the deposit amount is refundable to <code>buyer</code> at expiry
-	<code>_openOffer</code>: Boolean of whether the ChainLocker is open to any buyer address (<code>true</code>) or only the designated <code> buyer</code> address
-	<code>_valueCondition</code>: enum (uint8) of external data value condition for execution. Note that a ChainLocker user/deployer can arrange for a bespoke proxy contract that conforms to the IProxy interface (i.e. has a <code>read()</code> view function that returns a timestamp and int224 value), the returned ‘value’ can be used for any type of non-negative numerical data, and the “Both” ValueCondition can be leveraged to require a response between a minimum and maximum value or an exact response (by submitting the same value for <code>_minimumValue</code> and <code>_maximumValue</code>). Enum values are as follows:
    + 0 ('None'): no value contingency to ChainLocker execution; <code>_maximumValue</code>, <code>_minimumValue</code> and <code>_dataFeedProxyAddress</code> params are ignored;
    + 1 ('LessThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be <= <code>_maximumValue</code> when calling <code>execute()</code>; <code>_minimumValue</code> param is ignored;
    + 2 ('GreaterThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be >= <code>_minimumValue</code> when calling <code>execute()</code>; <code>_maximumValue</code> param is ignored
    + 3 ('Both'): the value returned from <code>_dataFeedProxyAddress</code> must be both <= <code>_maximumValue</code> and >= <code>_minimumValue</code> when calling <code>execute()</code> 
-	<code>_minimumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_maximumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_deposit</code>: uint256 amount of deposit, which must be <= <code>_totalAmount</code> and will be refunded to <code>buyer</code> at expiry if <code>refundable</code> == true;
-	<code>_totalAmount</code>: uint256 total amount of wei or tokens to be locked in ChainLocker;
-	<code>_expirationTime</code>: uint256 Unix time of ChainLocker’s expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the ChainLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_tokenContract</code>: address for the ERC20-compliant token contract used when deploying a TokenLocker; if deploying an EthLocker, pass address(0);
-	<code>_dataFeedProxy</code>: address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.

The ChainLockerFactory contract contains an inactive fee switch for deployments, but may be used in the future to automatically top-up data feed contracts for sustainability. Instead of using <code>deployChainLocker()</code>, users may bypass this contract entirely and instead directly deploy an EthLocker or TokenLocker. 

***


## EthLocker.sol

Non-custodial escrow smart contract using the native gas token as locked asset, and initiated with the following immutable parameters (supplied by the ChainLockerFactory’s <code>deployChainLocker()</code> function or directly in the EthLocker <code>constructor()</code>):
-	<code>_refundable</code>: Boolean of whether the deposit amount is refundable to <code>buyer</code> at expiry
-	<code>_openOffer</code>: Boolean of whether the EthLocker is open to any depositing address (<code>true</code>) or only the designated <code>buyer</code> address
-	<code>_valueCondition</code>: enum (uint8) of external data value condition for execution. Enum values are as follows (the same as specified above for <code>deployChainLocker()</code> in <code>ChainLockerFactory</code>):
    + 0 ('None'): no value contingency to execution; <code>_maximumValue</code>, <code>_minimumValue</code> and <code>_dataFeedProxyAddress</code> params are ignored;
    + 1 ('LessThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be <= <code>_maximumValue</code> when calling <code>execute()</code>; <code>_minimumValue</code> param is ignored;
    + 2	('GreaterThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be >= <code>_minimumValue</code> when calling <code>execute()</code>; <code>_maximumValue</code> param is ignored
    + 3 ('Both'): the value returned from <code>_dataFeedProxyAddress</code> must be both <= <code>_maximumValue</code> and >= <code>_minimumValue</code> when calling <code>execute()</code> 
-	<code>_minimumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_maximumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_deposit</code>: uint256 amount in wei of deposit, which must be <= <code>_totalAmount</code> and will be refunded to <code>buyer</code> at expiry if <code>refundable</code> == true;
-	<code>_totalAmount</code>: uint256 total amount in wei to be locked;
-	<code>_expirationTime</code>: uint256 Unix time of expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the EthLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_dataFeedProxy</code>: address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.

<code>Buyer</code> deposits into an EthLocker by sending the proper amount of wei directly to the contract address, invoking its <code>receive()</code> function. For open offers, the entire <code>totalAmount</code> must be deposited to become the <code>buyer</code>. 

If <code>seller</code> wishes to reject a depositor or <code>buyer</code>, seller may call <code>rejectDepositor()</code>, supplying the applicable address to be rejected (the applicable <code>amountWithdrawable</code> mapping will update for the amount the rejected address had previously deposited into the EthLocker). 

The <code>checkIfExpired()</code> function may also be called by any address at any time, and if it has indeed expired, the <code>amountWithdrawable</code> mapping(s) will update according to the deployer-defined refundability rules. 

Addresses with a nonzero <code>amountWithdrawable</code> mapped value can withdraw by calling <code>withdraw()</code>.

When each of <code>buyer</code> and <code>seller</code> are ready to execute the EthLocker, they must call <code>readyToExecute()</code>. Following this, any address may call <code>execute()</code>, and if the <code>totalAmount</code> is held by the EthLocker, <code>expirationTime</code> has not yet been met, and (if applicable) the <code>ValueCondition</code> is satisfied, the EthLocker will execute and send the <code>totalAmount</code> to <code>seller</code>. 


***


## TokenLocker.sol

Non-custodial escrow smart contract with mirrored functionality as ‘EthLocker’, but using an ERC20-compliant token as locked asset and the ability to lock such tokens via EIP2612 ‘permit’ function (if applicable). Initiated with the following immutable parameters (supplied by the ChainLockerFactory’s <code>deployChainLocker()</code> function or directly in the TokenLocker <code>constructor()</code>):
-	<code>_refundable</code>: Boolean of whether the deposit amount is refundable to <code>buyer</code> at expiry
-	<code>_openOffer</code>: Boolean of whether the TokenLocker is open to any depositing address (<code>true</code>) or only the designated <code>buyer</code> address
-	<code>_valueCondition</code>: enum (uint8) of external data value condition for execution. Enum values are as follows (the same as specified above for <code>deployChainLocker()</code> in <code>ChainLockerFactory</code>):
    + 0 ('None'): no value contingency to execution; <code>_maximumValue</code>, <code>_minimumValue</code> and <code>_dataFeedProxyAddress</code> params are ignored;
    + 1 ('LessThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be <= <code>_maximumValue</code> when calling <code>execute()</code>; <code>_minimumValue</code> param is ignored;
    + 2	('GreaterThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be >= <code>_minimumValue</code> when calling <code>execute()</code>; <code>_maximumValue</code> param is ignored
    + 3 ('Both'): the value returned from <code>_dataFeedProxyAddress</code> must be both <= <code>_maximumValue</code> and >= <code>_minimumValue</code> when calling <code>execute()</code> 
-	<code>_minimumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_maximumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_deposit</code>: uint256 token amount of deposit, which must be <= <code>_totalAmount</code> and will be refunded to <code>buyer</code> at expiry if <code>refundable</code> == true;
-	<code>_totalAmount</code>: uint256 total amount of tokens to be locked;
-	<code>_expirationTime</code>: uint256 Unix time of expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the TokenLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_tokenContract</code>: address for the ERC20-compliant token contract to be locked. Must be EIP2612-compliant for the buyer to use <code>depositTokensWithPermit()</code>;
-	<code>_dataFeedProxy</code>: address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.

<code>Buyer</code> deposits into an TokenLocker via either (A) <code>depositTokensWithPermit()</code> (if the applicable token contract has an EIP2612 permit() function) supplying the address that is transferring such tokens, the amount of tokens, and remainder of the permit() signature parameters (deadline, v, r, s), or (B) calling the token's <code>approve()</code> function supplying the address of the TokenLocker and the amount of tokens to be deposited, then calling <code>depositTokens()</code> in the TokenLocker supplying the address that approved the TokenLocker accordingly and is transferring such tokens, and the amount of tokens, in order to send the proper amount of tokens to the TokenLocker. For open offers, the entire <code>totalAmount</code> must be deposited to become the <code>buyer</code>. 

If <code>seller</code> wishes to reject a depositor or <code>buyer</code>, seller may call <code>rejectDepositor()</code>, supplying the applicable address to be rejected (the applicable <code>amountWithdrawable</code> mapping will update for the amount the rejected address had previously deposited into the TokenLocker). 

The <code>checkIfExpired()</code> function may also be called by any address at any time, and if it has indeed expired, the <code>amountWithdrawable</code> mapping(s) will update according to the deployer-defined refundability rules. 

Addresses with a nonzero <code>amountWithdrawable</code> mapped value can withdraw by calling <code>withdraw()</code>.

When each of <code>buyer</code> and <code>seller</code> are ready to execute the TokenLocker, they must call <code>readyToExecute()</code>. Following this, any address may call <code>execute()</code>, and if the <code>totalAmount</code> is held by the TokenLocker, <code>expirationTime</code> has not yet been met, and (if applicable) the <code>ValueCondition</code> is satisfied, the TokenLocker will execute and send the <code>totalAmount</code> to <code>seller</code>. 


***


## Receipt.sol

Informational contract which allows a user to receive an immutable receipt of a transaction's value in USD (if the asset has an active and funded <code>dataFeedProxy</code> supplied to the <code>tokenToProxy</code> mapping) by calling <code>printReceipt()</code>, supplying:
-	<code>_token</code>: address for the ERC20-compliant token contract (or address(0) for ETH/native gas token)
-	<code>_tokenAmount</code>: uint256 total amount of wei or tokens
-	<code>_decimals</code>: uint256 decimals of '_token' for USD value calculation (18 for wei)

Callers are also provided a <code>paymentId</code> if they print a receipt, which can be used to check their applicable USD value at any time by calling <code>paymentIdToUsdValue()</code>, supplying their paymentId as a parameter. Data feed proxy contracts may be added, updated, and removed only by this contract’s <code>admin</code>. 

As this contract is purely informational, optional, and never a contingency for a ChainLocker’s operation, ChainLockers remain entirely ownerless and non-custodial.

