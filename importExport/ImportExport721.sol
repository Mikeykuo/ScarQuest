// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract ImportExport721 is Ownable, Pausable, ReentrancyGuard {

    uint256 public time;

    struct infos {
        uint256[] imported;
        uint256[] exported;
        uint256[] claimed;   
    }

    mapping(address => bool) public admin;
    mapping (address => bool) public canExport;
    mapping (address => mapping (address => infos)) userData;
    mapping (address => mapping (address => mapping (uint256 => uint256))) public exportedTime;
    
    event Imported(address typeContract, address user, uint256[] tokenID);
    event Exported(address typeContract, address user, uint256[] tokenID);
    event Claimed(address typeContract, address user, uint256[] tokenID);

    modifier onlyAdmin() {
        require(admin[msg.sender] || msg.sender == owner(), "Not owner or admin");
        _;
    }

    function imports(address _type, uint256[] memory _tokenID ) external nonReentrant{
        require(_tokenID.length <= 20, "Import: Cannot import more than 20 tokens at once");

        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(msg.sender == IERC721(_type).ownerOf(_tokenID[i]), "Import: You are not the owner of this token");
            IERC721(_type).transferFrom(msg.sender, address(this), _tokenID[i]);
            userData[_type][msg.sender].imported.push(_tokenID[i]);
        }
        emit Imported(_type, msg.sender, _tokenID);
    }

    function importAndBurn(address _type, uint256[] memory _tokenID ) external nonReentrant{
        require(_tokenID.length <= 20, "Import: Cannot import more than 20 tokens at once");
        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(msg.sender == IERC721(_type).ownerOf(_tokenID[i]), "Import: You are not the owner of this token");
            IERC721(_type).safeTransferFrom(msg.sender, address(0), _tokenID[i]);
        }
        emit Imported(_type, msg.sender, _tokenID);
    }

    function Export(address _type, address userAddress, uint256[] memory _tokenID) external onlyAdmin {
        require(canExport[_type], "Export: This NFT is not exportable");
        require(_tokenID.length <= 20, "Export: Cannot export more than 20 tokens at once");
        //uint256 [] memory imported = userData[_type][msg.sender].imported;
        for(uint256 i=0; i<_tokenID.length; i++ ){  
             for(uint256 j=0; j<userData[_type][userAddress].imported.length; j++ ){
                if(userData[_type][userAddress].imported[j]!=0 && _tokenID[i]==userData[_type][userAddress].imported[j]){
                    userData[_type][userAddress].exported.push(_tokenID[i]);
                    exportedTime[_type][userAddress][_tokenID[i]]= block.timestamp;
                    //delete index
                    userData[_type][userAddress].imported[j]= userData[_type][userAddress].imported[userData[_type][userAddress].imported.length-1];
                    userData[_type][userAddress].imported.pop();
                }
             }
        }
        emit Exported(_type, userAddress, _tokenID);
    }

    function claim(address _type, uint256[] memory _tokenID) external nonReentrant {
        require(_tokenID.length <= 20, "Claim: Cannot claim more than 20 tokens at once");
        //uint256 [] memory exported = userData[_type][msg.sender].exported;
        for(uint256 i=0; i<_tokenID.length; i++ ){
            if(block.timestamp >= exportedTime[_type][msg.sender][_tokenID[i]] + time) {   
                for(uint256 j=0; j<userData[_type][msg.sender].exported.length; j++ ){
                    if(userData[_type][msg.sender].exported[j]!=0 && _tokenID[i]==userData[_type][msg.sender].exported[j]){
                        IERC721(_type).transferFrom(address(this), msg.sender, _tokenID[i]);
                        userData[_type][msg.sender].claimed.push(_tokenID[i]);
                        //delete index
                        userData[_type][msg.sender].exported[j]= userData[_type][msg.sender].exported[userData[_type][msg.sender].exported.length-1];
                        userData[_type][msg.sender].exported.pop();
                    }
                }
            }
        }
        emit Claimed(_type, msg.sender, _tokenID);
    }

    function withdrawToken(address _contract, address to, uint256[] memory _tokenID) external onlyOwner {
        for(uint256 i=0; i<_tokenID.length; i++ ){
            IERC721(_contract).transferFrom(address(this), to, _tokenID[i]);
        }
    }

    function getClaimable(address _type, address user) external view returns (uint256[] memory) {
        uint256[] memory tokenID = userData[_type][user].exported;
        uint256[] memory claimableToken = new uint256[](userData[_type][user].exported.length);
        for (uint256 i= 0; i<tokenID.length; i++){
            if (block.timestamp >= exportedTime[_type][msg.sender][tokenID[i]] + time){
                claimableToken[i]= tokenID[i];
            }
        }
        return claimableToken;
    }

    function getUserData(address _type, address user) external view returns (infos memory) {
        return userData[_type][user];
    }

    function setCanExport(address _contract, bool _status) external onlyOwner{
        canExport[_contract]= _status;
    }

    function setTime(uint256 _time) external onlyOwner{
        time= _time;
    }

    function setAdmin(address[] memory accounts, bool on) public onlyAdmin {
        for (uint256 i = 0; i < accounts.length; i++) {
            admin[accounts[i]] = on;
        }
    }

}