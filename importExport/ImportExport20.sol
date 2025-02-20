// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IPancakeRouter {
    function convertSCARtoUSDT(uint _amountSCAR) external view returns (uint amountOut);
    function convertUSDtoSCAR(uint _amountUSDT) external view returns (uint amountOut);
}


contract ImportExport20 is Ownable, Pausable, AccessControl, ReentrancyGuard, Initializable {

    IERC20 public SCAR;
    IPancakeRouter public router;
    address public moneyPool;
    address public taxReceiver;
    uint256 public timeDelay;

    bytes32 public constant EXPORTER_ROLE = keccak256("EXPORTER_ROLE");

    struct infos {
        uint256 imported;       // Amount imported
        uint256 exported;       // Amount exported
    }

    mapping (address => infos) userData;
    mapping(address => uint256) public exportedTime;

    uint256[5] public taxFees;
    uint256 public dailyLimit;
    uint256 public dailyExported;
    uint256 public lastExportTime;
    uint256 public percentBalance;
    address public multiSigWallet;
    uint256 public dailyTimeCycle;
    
    event Imported(address typeContract, address user, uint256 amount);
    event Exported(address typeContract, address user, uint256 amount);
    event Claimed(address typeContract, address user, uint256 amount);

    function initialize() initializer external {
        timeDelay = 300; // Claim time delay, initial value = 5 minutes
        SCAR = IERC20(0x8d9fB713587174Ee97e91866050c383b5cEE6209);
        _transferOwnership(_msgSender());
        router = IPancakeRouter(0x57e6f461179811260F2754Ed547C1073F8AA0751);
        moneyPool = 0x30aefaC0bd8829568d867526cA6df0c97c6c32Dc;
        taxReceiver = 0xBdc994a2CD7a35A075ea2e4942d9CE30Cd6659eF;

        _grantRole(DEFAULT_ADMIN_ROLE, owner());
        _grantRole(EXPORTER_ROLE, 0xd69ba5A28E91663C045f8a007C66C8486733B019);

    function imports(uint256 _amount) external whenNotPaused {
        require(SCAR.balanceOf(msg.sender) >= _amount, "Import: Your balance insufficient");
        SCAR.transferFrom(msg.sender, moneyPool, _amount);    
        userData[msg.sender].imported = userData[msg.sender].imported + _amount;
        emit Imported(address(SCAR), msg.sender, _amount);
    }

    // Export SCAR, only server can export
    function Export(address _receiver, uint256 _amount) external whenNotPaused onlyRole(EXPORTER_ROLE) {
        if (block.timestamp > lastExportTime + dailyTimeCycle) {
            dailyExported = 0;
            lastExportTime = block.timestamp;
            dailyLimit = percentBalance * SCAR.balanceOf(multiSigWallet) / 100;
        }
        require(dailyExported + _amount <= dailyLimit, "Daily export limit exceeded");
        uint256 tax = calculateTax(_amount);
        uint256 _amountToExport = _amount - tax;
        userData[_receiver].exported = userData[_receiver].exported + _amountToExport;
        SCAR.transferFrom(moneyPool, taxReceiver, tax);
        exportedTime[_receiver] = block.timestamp;
        dailyExported += _amount;
        emit Exported(address(SCAR), msg.sender, _amount);
    }

    function claim(uint256 _amount) external whenNotPaused nonReentrant {
        require(userData[msg.sender].exported >= _amount, "Claim: Cannot claim this amount");
        require(exportedTime[msg.sender] + timeDelay <= block.timestamp, "Claim: Cannot claim now. Try later");
        require(SCAR.balanceOf(moneyPool) >= _amount,  "Claim: Money pool funds insufficient");
        userData[msg.sender].exported = userData[msg.sender].exported - _amount;
        SCAR.transferFrom(moneyPool, msg.sender, _amount);
        delete exportedTime[msg.sender];
        emit Claimed(address(SCAR), msg.sender, _amount);
    }

    //Calculate import tax in SCAR
    function calculateTax(uint256 _amountSCAR) public view returns (uint256) {
        uint256 amountUSD = router.convertSCARtoUSDT(_amountSCAR);
        if (amountUSD < 1 ether) {
            uint256 tax = _amountSCAR * taxFees[0] / 100;
            return tax;
        } 
        else if (amountUSD>=1 ether && amountUSD<10 ether) {
            uint256 tax = _amountSCAR * taxFees[1] / 100;
            return tax;
        }
         else if (amountUSD>=10 ether && amountUSD<100 ether) {
            uint256 tax = _amountSCAR * taxFees[2] / 100;
            return tax;
        }

         else if (amountUSD>=100 ether && amountUSD<350 ether) {
            uint256 tax = _amountSCAR * taxFees[3] / 100;
            return tax;
        }
         else if (amountUSD>=350 ether ) {
            uint256 tax = _amountSCAR * taxFees[4] / 100;
            return tax;
        } else {
            return 0;
        }
    }

    // Return the amount of SCAR users can claim
    function getClaimable(address _user) external view returns (uint256) {
        return (userData[_user].exported);
    }

    // Return the date user can claim their SCAR after exporting
    function getDateClaimable(address _user) external view returns (uint256) {
        return (exportedTime[_user] + timeDelay);
    }

    function getUserData(address _user) external view returns (infos memory) {
        return (userData[_user]);
    }

    function getContractBalance() external view returns (uint256) {
        return SCAR.balanceOf(address(this));
    }

    function getRemainingAmount() external view returns (uint256) {
        uint256 remaining = dailyLimit - dailyExported;
        return remaining;
    }

    function withdrawSCAR(address to, uint256 _amounts) external onlyOwner {
        SCAR.transfer(to, _amounts);
    }

    function setTimeDelay(uint256 _time) external onlyOwner {
        timeDelay = _time;
    }

    function setSCARcontract(address _contract) external onlyOwner {
        SCAR = IERC20(_contract);
    }

    function setRouterContract(address _contract) external onlyOwner {
        router = IPancakeRouter(_contract);
    }

    function setMoneyPoolAddress(address _moneyPool) external onlyOwner {
        moneyPool = _moneyPool;
    }

    function setTaxReceiver(address _taxReceiver) external onlyOwner {
        taxReceiver = _taxReceiver;
    }

    function setTaxFees(uint256[5] memory _fees) external onlyOwner {
        taxFees = _fees;
    }

    function setPercentBalance(uint256 _percent) external onlyOwner {
        percentBalance = _percent;
    }

    function setMultiSigWallet(address _multisig) external onlyOwner {
        multiSigWallet = _multisig;
    }

    function setDailyLimit(uint256 _newLimit) external onlyOwner {
        dailyLimit = _newLimit * 10**18;
    }

    function setDailyTimeCycle(uint256 _time) external onlyOwner {
        dailyTimeCycle = _time;
    }

    function grantExporterRole(address _exporter) public onlyOwner {
        _grantRole(EXPORTER_ROLE, _exporter);
    }

}