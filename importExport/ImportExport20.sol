// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IPancakeRouter {
    function convertSCARtoUSDT(uint _amountSCAR) external view returns (uint amountOut);
    function convertUSDtoSCAR(uint _amountUSDT) external view returns (uint amountOut);
}


contract ImportExport20 is Ownable, Pausable, ReentrancyGuard, Initializable {

    IERC20 public SCAR;
    IPancakeRouter public router;
    address public moneyPool;
    uint256 public time;

    struct infos {
        uint256 imported;       // Amount imported
        uint256 exported;       // Amount exported
    }

    mapping (address => infos) userData;
    mapping(address => bool) public admin;
    mapping(address => uint256) public exportedTime;
    
    event Imported(address typeContract, address user, uint256 amount);
    event Exported(address typeContract, address user, uint256 amount);
    event Claimed(address typeContract, address user, uint256 amount);

    modifier onlyAdmin() {
        require(admin[msg.sender] || msg.sender == owner(), "Not owner or admin");
        _;
    }

    function initialize() initializer external {
        time = 300; // Claim time delay, initial value = 5 minutes
        SCAR = IERC20(0xf4c6a8b0F127c4e03DED1FE3f86795B5d0f4b677);
        _transferOwnership(_msgSender());
        router = IPancakeRouter(0xCa24d7C252CD4569a7a6921de36eBc40Dc130a1C);
        moneyPool = 0x1358b0Ea23d38683d64CF809F958deccE715F9E5;
    }

    function imports(uint256 _amount) external whenNotPaused {
        require(SCAR.balanceOf(msg.sender) >= _amount, "Import: Your balance insufficient");
        SCAR.transferFrom(msg.sender, moneyPool, _amount);    
        userData[msg.sender].imported = userData[msg.sender].imported + _amount;
        emit Imported(address(SCAR), msg.sender, _amount);
    }

    // Export SCAR, only admin accounts can export
    function Export(address _receiver, uint256 _amount) external whenNotPaused onlyAdmin {
        uint256 tax = calculateTax(_amount);
        uint256 _amountToExport = _amount - tax;
        userData[_receiver].exported = userData[_receiver].exported + _amountToExport;
        exportedTime[_receiver] = block.timestamp;
        emit Exported(address(SCAR), msg.sender, _amount);
    }

    function claim(uint256 _amount) external whenNotPaused {
        require(userData[msg.sender].exported >= _amount, "Claim: Cannot claim this amount");
        require(exportedTime[msg.sender] + time <= block.timestamp, "Claim: Cannot claim now. Try later");
        userData[msg.sender].exported = userData[msg.sender].exported - _amount;
        SCAR.transferFrom(moneyPool, msg.sender, _amount);
        delete exportedTime[msg.sender];
        emit Claimed(address(SCAR), msg.sender, _amount);
    }

    //Calculate import tax in SCAR
    function calculateTax(uint256 _amountSCAR) public view returns (uint256) {
        uint256 amountUSD = router.convertSCARtoUSDT(_amountSCAR);
        if (amountUSD < 1 ether) {
            uint256 tax = _amountSCAR * 30 / 100;
            return tax;
        } 
        else if (amountUSD>=1 ether && amountUSD<10 ether) {
            uint256 tax = _amountSCAR * 25 / 100;
            return tax;
        }
         else if (amountUSD>=10 ether && amountUSD<100 ether) {
            uint256 tax = _amountSCAR * 20 / 100;
            return tax;
        }

         else if (amountUSD>=100 ether && amountUSD<350 ether) {
            uint256 tax = _amountSCAR * 15 / 100;
            return tax;
        }
         else if (amountUSD>=350 ether ) {
            uint256 tax = _amountSCAR * 10 / 100;
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
        return (exportedTime[_user] + time);
    }

    function getUserData(address _user) external view returns (infos memory) {
        return (userData[_user]);
    }

    function getTokenBalance() external view returns (uint256) {
        return SCAR.balanceOf(address(this));
    }

    function withdrawSCAR(address to, uint256 _amounts) external onlyOwner{
        SCAR.transferFrom(address(this), to, _amounts);
    }

    function setTime(uint256 _time) external onlyOwner {
        time = _time;
    }

    function setSCARcontract(address _contract) external onlyOwner {
        SCAR = IERC20(_contract);
    }

    function setRouterContract(address _contract) external onlyOwner {
        router = IPancakeRouter(_contract);
    }

    function setMoneyPoolAddress(address _receiver) external onlyOwner {
        moneyPool = _receiver;
    }

    function setAdmin(address[] memory accounts, bool on) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            admin[accounts[i]] = on;
        }
    }

}