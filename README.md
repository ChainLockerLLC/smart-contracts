# ChainLocker Smart Contracts

_Please note that all code, files, forms, templates, or other materials provided or linked herein (the "Repo Contents") are provided strictly as-is under the MIT License; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of any of the Repo Contents or any smart contracts or other software deployed from these files._

_Any users, developers, or adapters of the Repo Contents or any deployments or instances thereof should proceed with caution and use at their own risk._


O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O

ChainLocker is a non-custodial, user-defined-and-deployed escrow deployment protocol. Each ChainLocker is a separate contract deployment, and is designed to only hold one type of asset. The locked assets are programmatically released provided all deployer-defined conditions are met when <code>execute()</code> is called, including optional oracle-fed data conditions which are known as “value conditions,” or otherwise transferred at the deployer-defined expiry time according to the deployer-defined deposit and refundability rules. 

O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O


__ChainLockerFactory.sol__: factory contract for ChainLocker deployments (TokenLocker or EthLocker) based upon the various parameters passed to <code>deployChainLocker()</code>. Has a fee switch for deployments using this factory, which is initially off. For deployments with a non-zero <code>ValueCondition</code>, the execution of the ChainLocker pre-expiry is reliant upon the accurate operation and security of the applicable <code>dataFeedProxy</code> contract (specifically its <code>read()</code> function) so users are advised to carefully verify and monitor such contract. The parameters for a ChainLocker deployment by calling <code>deployChainLocker()</code> are:

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
-	<code>_totalAmount</code>: uint256 total amount to be locked in ChainLocker;
-	<code>_expirationTime</code>: uint256 Unix time of ChainLocker’s expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the ChainLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_tokenContract</code> contract address for the ERC20-compliant token used when deploying a TokenLocker; if deploying an EthLocker, pass address(0);
-	<code>_dataFeedProxy</code> address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.
  

O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O


____EthLocker.sol____: non-custodial escrow smart contract with native gas token as locked asset, with the following parameters (as may be supplied by the ChainLockerFactory’s <code>deployChainLocker()</code> function or directly in the EthLocker <code>constructor()</code>:
-	<code>_refundable</code>: Boolean of whether the deposit amount is refundable to <code>buyer</code> at expiry
-	<code>_openOffer</code>: Boolean of whether the EthLocker is open to any buyer address (<code>true</code>) or only the designated <code> buyer</code> address
-	<code>_valueCondition</code>: enum (uint8) of external data value condition for execution. Enum values are as follows (the same as specified above for <code>deployChainLocker()</code> in <code>ChainLockerFactory</code>):
    + 0 ('None'): no value contingency to ChainLocker execution; <code>_maximumValue</code>, <code>_minimumValue</code> and <code>_dataFeedProxyAddress</code> params are ignored;
    + 1 ('LessThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be <= <code>_maximumValue</code> when calling <code>execute()</code>; <code>_minimumValue</code> param is ignored;
    + 2	('GreaterThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be >= <code>_minimumValue</code> when calling <code>execute()</code>; <code>_maximumValue</code> param is ignored
    + 3 ('Both'): the value returned from <code>_dataFeedProxyAddress</code> must be both <= <code>_maximumValue</code> and >= <code>_minimumValue</code> when calling <code>execute()</code> 
-	<code>_minimumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_maximumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_deposit</code>: uint256 amount in wei of deposit, which must be <= <code>_totalAmount</code> and will be refunded to <code>buyer</code> at expiry if <code>refundable</code> == true;
-	<code>_totalAmount</code>: uint256 total amount in wei to be locked in ChainLocker;
-	<code>_expirationTime</code>: uint256 Unix time of ChainLocker’s expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the ChainLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_dataFeedProxy</code> address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.

Buyer deposits into an EthLocker by sending the proper amount of wei directly to the contract address, invoking its <code>receive()</code> function. 

If <code>openOffer</code> == true, and <code>seller</code> wishes to reject a depositor or <code>buyer</code>, seller may call <code>rejectDepositor()</code>, supplying the applicable address to be rejected. 


When each of <code>buyer</code> and <code>seller</code> are ready to execute the EthLocker, they must call <code>readyToExecute()</code>. Following this, any address may call <code>execute()</code>, and if the <code>totalAmount</code> is held by the ChainLocker, <code>expirationTime</code> has not yet been met, and (if applicable) the <code>ValueCondition</code> is satisfied, the EthLocker will execute. 

The <code>checkIfExpired()</code> function may also be called by any address at any time, and if it has indeed expired, the locked assets will be transferred according to the deployer-defined refundability rules. 

O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O


____TokenLocker.sol____: non-custodial escrow smart contract with mirrored functionality as ‘EthLocker’, but with an ERC20 token as locked asset and the ability to lock such tokens via EIP2612 ‘permit’ function (if applicable). Uses the following parameters (as may be supplied by the ChainLockerFactory’s <code>deployChainLocker()</code> function or directly in the TokenLocker <code>constructor()</code>:
-	<code>_refundable</code>: Boolean of whether the deposit amount is refundable to <code>buyer</code> at expiry
-	<code>_openOffer</code>: Boolean of whether the TokenLocker is open to any buyer address (<code>true</code>) or only the designated <code> buyer</code> address
-	<code>_valueCondition</code>: enum (uint8) of external data value condition for execution. Enum values are as follows (the same as specified above for <code>deployChainLocker()</code> in <code>ChainLockerFactory</code>):
    + 0 ('None'): no value contingency to ChainLocker execution; <code>_maximumValue</code>, <code>_minimumValue</code> and <code>_dataFeedProxyAddress</code> params are ignored;
    + 1 ('LessThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be <= <code>_maximumValue</code> when calling <code>execute()</code>; <code>_minimumValue</code> param is ignored;
    + 2	('GreaterThanOrEqual'): the value returned from <code>_dataFeedProxyAddress</code> must be >= <code>_minimumValue</code> when calling <code>execute()</code>; <code>_maximumValue</code> param is ignored
    + 3 ('Both'): the value returned from <code>_dataFeedProxyAddress</code> must be both <= <code>_maximumValue</code> and >= <code>_minimumValue</code> when calling <code>execute()</code> 
-	<code>_minimumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_maximumValue</code>: int224 for <code>ValueCondition</code> check in <code>execute()</code> as set forth above, if applicable;
-	<code>_deposit</code>: uint256 token amount of deposit, which must be <= <code>_totalAmount</code> and will be refunded to <code>buyer</code> at expiry if <code>refundable</code> == true;
-	<code>_totalAmount</code>: uint256 total amount of tokens to be locked in ChainLocker;
-	<code>_expirationTime</code>: uint256 Unix time of ChainLocker’s expiry;
-	<code>_seller</code>: address payable of the seller (ultimate recipient of totalAmount should the ChainLocker execute). Replaceable by <code>seller</code> post-deployment by calling <code>updateSeller</code> with the new address payable;
-	<code>_buyer</code>: address payable of the buyer (depositor of deposit/totalAmount and recipient of deposit’s return at expiry if <code>refundable</code> == true). Replaceable by <code>buyer</code> post-deployment by calling <code>updateBuyer</code> with the new address payable. Ignored if <code>openOffer</code> == true;
-	<code>_tokenContract</code> contract address for the ERC20-compliant token to be locked. Must be EIP2612 compliant for the buyer to use <code>depositTokensWithPermit()</code>;
-	<code>_dataFeedProxy</code> address which will be called if <code>_valueCondition</code> > 0 in <code>execute</code> which must correctly implement the <code>read()</code> function as defined in the <code>IProxy interface</code>. Intended to utilize API3’s dAPIs.

Buyer deposits into an TokenLocker via either (A) <code>depositTokensWithPermit()</code> (if the applicable token contract has an EIP2612 permit() function) supplying the address that is transferring such tokens, the amount of tokens, and remainder of the permit() signature parameters (deadline, v, r, s), or (B) calling the token's <code>approve()</code> function supplying the address of the TokenLocker and the amount of tokens to be deposited, then calling <code>depositTokensWithPermit()</code> in the TokenLocker supplying the address that approved the TokenLocker accordingly and is transferring such tokens, and the amount of tokens, in order to send the proper amount of tokens to the TokenLocker. 

If <code>openOffer</code> == true, and <code>seller</code> wishes to reject a depositor or <code>buyer</code>, seller may call <code>rejectDepositor()</code>, supplying the applicable address to be rejected. 

When each of <code>buyer</code> and <code>seller</code> are ready to execute the EthLocker, they must call <code>readyToExecute()</code>. Following this, any address may call <code>execute()</code>, and if the <code>totalAmount</code> is held by the ChainLocker, <code>expirationTime</code> has not yet been met, and (if applicable) the <code>ValueCondition</code> is satisfied, the EthLocker will execute. 

The <code>checkIfExpired()</code> function may also be called by any address at any time, and if it has indeed expired, the locked tokens will be transferred according to the deployer-defined refundability rules. 

O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O=O


____Receipt.sol____: informational contract which allows a user to receive an immutable receipt of a transaction's value in USD (if the asset has a proper <code>dataFeedProxy</code> supplied to the <code>tokenToProxy</code> mapping) by calling <code>printReceipt()</code>. Callers are also provided a <code>paymentId</code> if they print a receipt, which can be used to check their applicable USD value at any time by calling <code>paymentIdToUsdValue()</code>, supplying their paymentId as a parameter. Data feed proxy contracts may be added, updated, and removed only by this contract’s <code>admin</code>. As this contract is purely informational, optional, and never a contingency for a ChainLocker’s operation, the remainder of the ChainLocker protocol remains entirely ownerless and non-custodial.

