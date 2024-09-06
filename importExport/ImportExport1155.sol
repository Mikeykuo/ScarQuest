// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IERC1155 {
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external;
    function mintBatch(address account, uint256[] calldata tokenIds, uint256[] calldata amounts, bytes calldata data) external;
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external;
}


contract ImportExport1155 is Ownable, Pausable, IERC1155Receiver, ReentrancyGuard, Initializable {

    struct infos {
        uint256[] tokenIDs;                          // Imported token ids
        mapping (uint256 => uint256) imported;       // Amount imported
        mapping (uint256 => uint256) exported;       // Amount imported
    }

    mapping(address => bool) public admin;
    mapping (address => bool) public canImport;
    mapping (address => bool) public canExport;     // Token that can be exported
    mapping (address => mapping (address => infos)) userData; 
    
    event Imported(address typeContract, address user, uint256[] tokenID, uint256[] amount);
    event Exported(address typeContract, address user, uint256[] tokenID, uint256[] amount);
    event Claimed(address typeContract, address user, uint256[] tokenID, uint256[] amount);

    modifier onlyAdmin() {
        require(admin[msg.sender] || msg.sender == owner(), "Not owner or admin");
        _;
    }

    function initialize() initializer external {
        _transferOwnership(_msgSender());
    }

    function imports(address _type, uint256[] memory _tokenID, uint256[] memory _amount) external whenNotPaused {
        require(canImport[_type], "Import: This NFT is not importable");
        require(_tokenID.length <= 20 && _amount.length <= 20, "Import: Cannot import more than 20 tokens at once");
        require(_tokenID.length == _amount.length, "Import: Array length mismatch");

        IERC1155(_type).safeBatchTransferFrom(msg.sender, address(this), _tokenID, _amount, "0x00");
        for(uint256 i=0; i<_tokenID.length; i++ ){
            bool found = false;
            for(uint256 j=0; j<userData[_type][msg.sender].tokenIDs.length; j++ ){
                if(_tokenID[i] == userData[_type][msg.sender].tokenIDs[j]){
                    found = true;
                    break;
                }
            }
            if(!found){
                userData[_type][msg.sender].tokenIDs.push(_tokenID[i]);
            }
            userData[_type][msg.sender].imported[_tokenID[i]]= userData[_type][msg.sender].imported[_tokenID[i]] + _amount[i];
        }
        emit Imported(_type, msg.sender, _tokenID, _amount);
    }

    //importAndBurn: Import users tokenIds into the game, and burn them onChain
    function importAndBurn(address _type, uint256[] memory _tokenID, uint256[] memory _amount) external whenNotPaused {
        require(canImport[_type], "ImportAndBurn: This NFT is not importable");
        require(_tokenID.length <= 20 && _amount.length <= 20, "ImportAndBurn: Cannot import more than 20 tokens at once");
        require(_tokenID.length == _amount.length, "ImportAndBurn: Array length mismatch");

        IERC1155(_type).burnBatch(msg.sender, _tokenID, _amount);
        for(uint256 i=0; i<_tokenID.length; i++ ){
            bool found = false;
            for(uint256 j=0; j<userData[_type][msg.sender].tokenIDs.length; j++ ){
                if(_tokenID[i] == userData[_type][msg.sender].tokenIDs[j]){
                    found = true;
                    break;
                }
            }
            if(!found){
                userData[_type][msg.sender].tokenIDs.push(_tokenID[i]);
            }
            userData[_type][msg.sender].imported[_tokenID[i]]= userData[_type][msg.sender].imported[_tokenID[i]] + _amount[i];
        }
        emit Imported(_type, msg.sender, _tokenID, _amount);
    }

    function Export(address _type, address userAddress, uint256[] memory _tokenID, uint256[] memory _amount) external whenNotPaused onlyAdmin {
        require(canExport[_type], "Export: This NFT is not exportable");
        require(_tokenID.length <= 20 && _amount.length <= 20, "Export: Cannot export more than 20 tokens at once");
        require(_tokenID.length == _amount.length, "Export: Array length mismatch");

        uint256 [] memory tokenIDs = userData[_type][userAddress].tokenIDs;
        
        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(userData[_type][userAddress].imported[_tokenID[i]] >= _amount[i], "Export: You can only Export tokens you own");
            for(uint256 j=0; j<tokenIDs.length; j++ ){
                if(_tokenID[i]==tokenIDs[j]){
                    userData[_type][userAddress].exported[tokenIDs[j]]= userData[_type][userAddress].exported[tokenIDs[j]] + _amount[i];
                    userData[_type][userAddress].imported[tokenIDs[j]]= userData[_type][userAddress].imported[tokenIDs[j]] - _amount[i];
                }
            }
        }
        emit Exported(_type, userAddress, _tokenID, _amount);
    }

    // ExportMint: Mint new token for the user
    function ExportMint(address _type, address userAddress, uint256[] memory _tokenID, uint256[] memory _amount) external whenNotPaused onlyAdmin {
        require(canExport[_type], "ExportMint: This NFT is not exportable");
        require(_tokenID.length <= 20 && _amount.length <= 20, "ExportMint: Cannot export more than 20 tokens at once");
        require(_tokenID.length == _amount.length, "ExportMint: Array length mismatch");

        uint256 [] memory tokenIDs = userData[_type][userAddress].tokenIDs;
        
        for(uint256 i=0; i<_tokenID.length; i++ ){
            bool found = false;
            for(uint256 j=0; j<tokenIDs.length; j++ ){
                if(_tokenID[i] == userData[_type][userAddress].tokenIDs[j]){
                    found = true;
                    break;
                }
            }
            if(!found){
                userData[_type][userAddress].tokenIDs.push(_tokenID[i]);
            }
            userData[_type][userAddress].exported[_tokenID[i]]= userData[_type][userAddress].exported[_tokenID[i]] + _amount[i];
        }
        IERC1155(_type).mintBatch(address(this), _tokenID, _amount, "0x00");
        emit Exported(_type, userAddress, _tokenID, _amount);
    }

    function claim(address _type, uint256[] memory _tokenID, uint256[] memory _amount) external whenNotPaused nonReentrant {
        require(_tokenID.length <= 20, "Claim: Cannot claim more than 20 tokens at once");
        require(_tokenID.length == _amount.length, "Claim: Array length mismatch");
        infos storage datas = userData[_type][msg.sender];
        uint256 [] memory tokenIDs = userData[_type][msg.sender].tokenIDs;
        
        for(uint256 i=0; i<_tokenID.length; i++ ){
            require(datas.exported[_tokenID[i]] >= _amount[i], "Claim: You can only claim tokens you own");
            for(uint256 j=0; j<datas.tokenIDs.length; j++ ){
                if(_tokenID[i]==datas.tokenIDs[j]){
                    userData[_type][msg.sender].exported[tokenIDs[j]]= userData[_type][msg.sender].exported[tokenIDs[j]] - _amount[i];
                }
            }
        }
        IERC1155(_type).safeBatchTransferFrom(address(this), msg.sender, _tokenID, _amount, "0x00");
        emit Claimed(_type, msg.sender, _tokenID, _amount);
    }

    function getClaimable(address _type, address user) external view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory tokenID = userData[_type][user].tokenIDs;
        uint256[] memory _amount = new uint256[](userData[_type][user].tokenIDs.length);
        for (uint256 i= 0; i<tokenID.length; i++){
                _amount[i]= userData[_type][user].exported[tokenID[i]];   
        }
        return (tokenID, _amount);
    }

    function getUserData(address _type, address user) external view 
    returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        uint256[] memory _tokenIDs = userData[_type][user].tokenIDs;
        uint256[] memory _imported = new uint256[] (userData[_type][user].tokenIDs.length);
        uint256[] memory _exported= new uint256[] (userData[_type][user].tokenIDs.length);

        for(uint256 i=0; i<_tokenIDs.length; i++){
            _imported[i]= userData[_type][user].imported[_tokenIDs[i]];
        }
        
        for(uint256 i=0; i<_tokenIDs.length; i++){
            _exported[i]= userData[_type][user].exported[_tokenIDs[i]];
        }
        return (_tokenIDs, _imported, _exported);
    }

    function setCanImport(address _contract, bool _status) external onlyOwner{
        canImport[_contract] = _status;
    }

    function setCanExport(address _contract, bool _status) external onlyOwner {
        canExport[_contract]= _status;
    }

    function withdrawToken(address _contract, address to, uint256[] memory _tokenIds, uint256[] memory _amounts) external onlyOwner {
        IERC1155(_contract).safeBatchTransferFrom(address(this), to, _tokenIds, _amounts, "0x00");
    }

    function setAdmin(address[] memory accounts, bool on) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            admin[accounts[i]] = on;
        }
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
      //require(from == address(0x0), "Cannot Receive NFTs Directly");
      // return IERC721Receiver.onERC721Received.selector;
      return IERC1155Receiver.onERC1155Received.selector;
    }
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
      //require(from == address(0x0), "Cannot Receive NFTs Directly");
      return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
    return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }

}