// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function balanceOf(address owner) external view returns (uint256 balance);
    function burn(uint256 tokenId) external;
    function mint(address to) external;
    function mintBatch(address to, uint256 _amount) external returns (uint256[] memory);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}


contract ImportExport721 is Ownable, Pausable, AccessControl, ReentrancyGuard, IERC721Receiver, Initializable {

    uint256 public countExport;
    uint256 public maxExport;
    uint256 public timeDelay;
    uint256 public maxTokensAllowed;
    bytes32 public constant EXPORTER_ROLE = keccak256("EXPORTER_ROLE");
    bytes32 public constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");

    struct infos {
        uint256[] imported;
        uint256[] exported;
        uint256[] claimed;
    }

    mapping (address => bool) public canImport;
    mapping (address => bool) public canExport;
    mapping (address => mapping (address => infos)) userData;
    mapping (address => mapping (address => mapping (uint256 => uint256))) public exportedTime;
    
    event Imported(address typeContract, address user, uint256[] tokenID);
    event Exported(address typeContract, address user, uint256[] tokenID);
    event ExporteMinted(address typeContract, address user, uint256 _amount);
    event Claimed(address typeContract, address user, uint256[] tokenID);


    function initialize() initializer external {
        timeDelay = 86400; // Claim time delay, initial value =  1 day
        maxExport = 200; // Maximum amount of export set by the multisig wallet
        maxTokensAllowed = 20; // Maximum amount of tokens that can be imported/exported/claimed at once
        _transferOwnership(_msgSender());

        _grantRole(DEFAULT_ADMIN_ROLE, owner());
        _grantRole(EXPORTER_ROLE, 0xd69ba5A28E91663C045f8a007C66C8486733B019);
        _grantRole(MULTISIG_ROLE, 0x30aefaC0bd8829568d867526cA6df0c97c6c32Dc);
    }

    function imports(address _type, uint256[] memory _tokenID ) external whenNotPaused {
        require(canImport[_type], "Import: This NFT is not importable");
        require(_tokenID.length <= maxTokensAllowed, "Import: Cannot import more than the maximum allowed tokens at once");
        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(msg.sender == IERC721(_type).ownerOf(_tokenID[i]), "Import: You are not the owner of this token");
            IERC721(_type).transferFrom(msg.sender, address(this), _tokenID[i]);
            userData[_type][msg.sender].imported.push(_tokenID[i]);
        }
        emit Imported(_type, msg.sender, _tokenID);
    }

    function importAndBurn(address _type, uint256[] memory _tokenID ) external whenNotPaused {
        require(canImport[_type], "ImportAndBurn: This NFT is not importable");
        require(_tokenID.length <= maxTokensAllowed, "ImportAndBurn: Cannot import more than the maximum allowed tokens at once");
        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(msg.sender == IERC721(_type).ownerOf(_tokenID[i]), "ImportAndBurn: You are not the owner of this token");
            IERC721(_type).burn(_tokenID[i]);
            userData[_type][msg.sender].imported.push(_tokenID[i]);
        }
        emit Imported(_type, msg.sender, _tokenID);
    }

    function Export(address _type, address userAddress, uint256[] memory _tokenID) external whenNotPaused {
        require(hasRole(EXPORTER_ROLE, msg.sender), "Export: Caller does not have EXPORTER_ROLE");
        require(canExport[_type], "Export: This NFT is not exportable");
        require(_tokenID.length <= maxTokensAllowed, "Export: Cannot export more than the maximum allowed tokens at once");
        require((countExport+_tokenID.length) <= maxExport, "Export: Cannot export more than allocated amount of export");
        for(uint256 i=0; i<_tokenID.length; i++ ){  
            userData[_type][userAddress].exported.push(_tokenID[i]);
            exportedTime[_type][userAddress][_tokenID[i]]= block.timestamp;

            //If tokenID already imported delete index in imported array
            for(uint256 j=0; j<userData[_type][userAddress].imported.length; j++ ){
                if(userData[_type][userAddress].imported[j]!=0 && _tokenID[i]==userData[_type][userAddress].imported[j]){
                    //delete index
                    userData[_type][userAddress].imported[j]= userData[_type][userAddress].imported[userData[_type][userAddress].imported.length-1];
                    userData[_type][userAddress].imported.pop();
                }
            }
        }
        countExport += _tokenID.length ;
        emit Exported(_type, userAddress, _tokenID);
    }

    function ExportMint(address _type, address userAddress, uint256 _amount) external whenNotPaused {
        require(hasRole(EXPORTER_ROLE, msg.sender),  "Export: Caller does not have EXPORTER_ROLE");
        require(canExport[_type], "Export: This NFT is not exportable");
        require(_amount <= maxTokensAllowed, "Export: Cannot export more than the maximum allowed tokens at once");
        require((countExport+_amount) <= maxExport, "Export: Cannot export more than the max allocated amount");

        uint256[] memory _tokenIDs = IERC721(_type).mintBatch(address(this), _amount);
        for(uint256 i=0; i<_amount; i++ ){
            userData[_type][userAddress].exported.push(_tokenIDs[i]);
            exportedTime[_type][userAddress][_tokenIDs[i]]= block.timestamp;
        }
        countExport += _amount ;
        emit Exported(_type, userAddress, _tokenIDs);
    }

    function claim(address _type, uint256[] memory _tokenID) external nonReentrant whenNotPaused {
        require(_tokenID.length <= maxTokensAllowed, "Claim: Cannot claim more than the maximum allowed tokens at once");
        uint256 [] memory exported = userData[_type][msg.sender].exported;
        for(uint256 i=0; i<_tokenID.length; i++ ){
            _checkArray(_tokenID[i], exported);
            require(block.timestamp >= exportedTime[_type][msg.sender][_tokenID[i]] + timeDelay, "Claim: Cannot claim now. Try later!");
            if(block.timestamp >= exportedTime[_type][msg.sender][_tokenID[i]] + timeDelay) {   
                for(uint256 j=0; j<userData[_type][msg.sender].exported.length; j++ ){
                    if(userData[_type][msg.sender].exported[j]!=0 && _tokenID[i]==userData[_type][msg.sender].exported[j]){
                        IERC721(_type).transferFrom(address(this), msg.sender, _tokenID[i]);
                        userData[_type][msg.sender].claimed.push(_tokenID[i]);
                        //delete index
                        userData[_type][msg.sender].exported[j]= userData[_type][msg.sender].exported[userData[_type][msg.sender].exported.length-1];
                        userData[_type][msg.sender].exported.pop();
                        delete exportedTime[_type][msg.sender][_tokenID[i]];
                    }
                }
            }
        }
        emit Claimed(_type, msg.sender, _tokenID);
    }

    // Helper function
    function _checkArray(uint _number, uint[] memory _array) internal pure {
        bool found = false;
        for (uint i = 0; i < _array.length; i++) {
            if (_array[i] == _number) {
                found = true;
                break;
            }
        }
        require(found, "_checkArray: tokenID not found in array");
    }

    function withdrawToken(address _contract, address to, uint256[] memory _tokenID) external onlyOwner {
        for(uint256 i=0; i<_tokenID.length; i++ ){
            IERC721(_contract).transferFrom(address(this), to, _tokenID[i]);
        }
    }

    // Return the tokenIDs a user can claim
    function getClaimable(address _type, address _user) external view returns (uint256[] memory) {
        uint256[] memory tokenID = userData[_type][_user].exported;
        uint256[] memory claimableToken = new uint256[](userData[_type][_user].exported.length);
        for (uint256 i= 0; i<tokenID.length; i++){
            claimableToken[i] = tokenID[i];
        }
        return claimableToken;
    }

    function getDateClaimable(address _type, address _userAddress, uint256 _tokenID) external view returns (uint256) {
        if (exportedTime[_type][_userAddress][_tokenID] == 0) {
            return 0;
        } else {
            return (exportedTime[_type][_userAddress][_tokenID] + timeDelay);
        }
    }

    function getUserData(address _type, address _user) external view returns (infos memory) {
        return userData[_type][_user];
    }

    function setCanImport(address _contract, bool _status) external onlyOwner {
        canImport[_contract] = _status;
    }

    function setCanExport(address _contract, bool _status) external onlyOwner {
        canExport[_contract] = _status;
    }

    function setTimeDelay(uint256 _time) external onlyOwner {
        timeDelay = _time;
    }

    function setMaxExport(uint256 _amount) external {
        require(hasRole(MULTISIG_ROLE, msg.sender), "setMaxExport: Caller does not have MULTISIG_ROLE");
        maxExport = _amount;
    }

    function resetCountExport() external {
        require(hasRole(MULTISIG_ROLE, msg.sender), "resetCountExport: Caller does not have MULTISIG_ROLE");
        countExport = 0;
    }

    function setMaxTokensAllowed(uint256 _amount) external onlyOwner {
        maxTokensAllowed = _amount;
    }

    function grantExporterRole(address _exporter) public onlyOwner {
        _grantRole(EXPORTER_ROLE, _exporter);
    }

    function grantMultisigRole(address _address) public onlyOwner {
        _grantRole(MULTISIG_ROLE, _address);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

}