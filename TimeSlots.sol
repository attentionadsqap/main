// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Credits.sol";

contract TimeSlots is ERC721("Ads Protocol Timeslot Token", "ADS") {

    // Time Constants
    uint public constant SLOT_DURATION = 15 seconds;
    uint public constant AUCTION_TIMEDELTA = 90 days; // Note: should this be longer? how early do advertisers need to know whether they won the slot? how much time should the slot be in the open market?
    uint public /* immutable */ T_0;

    // Links
    IERC20 public /* constant */ USDC;
    Credits public /* constant */ creditsToken;

    // Structs
    struct Timeslot {
        address highestBidder; // Todo: maybe change to highestBidder?
        string ipfsCid;
        uint userCount;
        uint upPreferences;
        uint downPreferences;
    }

    // Preferences
    uint maxUpPreference = 5;
    uint maxDownPreference = 5;

    // State
    mapping(uint id => Timeslot) internal slots;
    mapping(uint id => mapping(address user => uint bid)) internal slotUserBids;
    mapping(uint id => mapping(address user => uint preference)) internal slotUserPreferences;

    // Libs
    using SafeERC20 for IERC20;

    // Question: should this be zero-indexed or not?
    function currentSlotId() private view returns(uint) {
        return (block.timestamp - T_0) / SLOT_DURATION + 1; // Note: first timeslotId is 1 (not zero-indexed)
    }

    function currentAd() public view returns(string memory ipfsCid) {
        ipfsCid = slots[currentSlotId()].ipfsCid;
    }

    function slotStartTime(uint slotId) private pure returns (uint) {
        return (slotId - 1) * SLOT_DURATION; // Note: first timeslotId is 1 (not zero-indexed)
    }

    function timeUntilSlotStart(uint slotId) private view returns(uint) {
        return slotStartTime(slotId) - block.timestamp;
    }

    function slotAuctionOver(uint slotId) public view returns(bool) {
        return timeUntilSlotStart(slotId) <= AUCTION_TIMEDELTA;
    }

    function slotHighestBid(uint slotId) public view returns(uint) {
        address highestBidder = slots[slotId].highestBidder;
        return slotUserBids[slotId][highestBidder];
    }

    // Todo: if user cancels bid, give him his credits back
    function bid(uint slotId, uint amount, uint credits, string calldata ipfsCid) external {
        require(!slotAuctionOver(slotId), "slot auction over");
        require(slotUserBids[slotId][msg.sender] == 0, "you already bid on this timeslot");
        Timeslot storage timeslot = slots[slotId];
        require(amount > slotHighestBid(slotId), "bid must > highestBid");

        // Burn credits
        creditsToken.burn(msg.sender, credits);

        // Pull bid (amount - credits)
        USDC.safeTransferFrom(msg.sender, address(this), amount - credits);

        // Store bid
        slotUserBids[slotId][msg.sender] = amount;

        // Update timeslot
        timeslot.highestBidder = msg.sender;
        timeslot.ipfsCid = ipfsCid;
    }

    // Todo: ensure minting a slotId that already exists throws error
    function mint(address to, uint slotId) external {
        require(slotAuctionOver(slotId), "slot auction not over");
        require(msg.sender == slots[slotId].highestBidder, "not highest bidder");
        _safeMint(to, slotId);
    }

    // Todo: if highest bidder wants to change ads, he'll have to mint first. fix later
    function updateSlotAd(uint slotId, string calldata ipfsCid) external {
        require(msg.sender == ownerOf(slotId), "only slot owner can update it's ad");
        slots[slotId].ipfsCid = ipfsCid;
    }

    function upVote(uint preference) external {

        // Get currentSlotId
        uint _currentSlotId = currentSlotId();

        // Validate
        require(!voted(msg.sender, _currentSlotId), "you already voted for this slot");
        require(preference > 0 && preference <= maxUpPreference, "invalid preference");

        // Update Slot
        slots[_currentSlotId].userCount ++;
        slots[_currentSlotId].upPreferences += preference;
        slotUserPreferences[_currentSlotId][msg.sender] = preference;
    }

    function downVote(uint preference) external {
        
        // Get currentSlotId
        uint _currentSlotId = currentSlotId();

        // Validate
        require(!voted(msg.sender, _currentSlotId), "you already voted for this slot");
        require(preference > 0 && preference <= maxDownPreference, "invalid preference");

        // Update Slot
        slots[_currentSlotId].userCount ++;
        slots[_currentSlotId].downPreferences += preference;
        slotUserPreferences[_currentSlotId][msg.sender] = preference;
    }

    // Todo: block users from pulling from the same slot twice
    function pullReward(uint slotId) external {

        // Validate
        require(slotId < currentSlotId(), "timeslot not over");
        require(voted(msg.sender, slotId), "user didn't vote in this timeslot");

        // Calculate reward
        Timeslot memory timeslot = slots[slotId];
        uint reward = slotHighestBid(slotId) / timeslot.userCount;

        // Send reward to user
        USDC.safeTransfer(msg.sender, reward);
    }

    function voted(address account, uint slotId) private view returns(bool) {
        return slotUserPreferences[slotId][account] != 0;
    }

    // Todo: block advertisers from minting credits for the same slot twice
    function pullReimbursement(uint slotId) external {
        require(msg.sender == ownerOf(slotId), "only owner can pull reimbursement"); // Note: maybe advertisers will be able to transfer NFTs and allow to receiver call this

        // Get slot
        Timeslot memory slot = slots[slotId];

        // Calculate credits
        uint credits = upPreferenceRate(slot) * slot.userCount;

        // Mint Credits to Advertiser
        creditsToken.mint(msg.sender, credits);
    }

    function upPreferenceRate(Timeslot memory slot) private pure returns(uint) {
        return slot.upPreferences / totalPreferences(slot);
    }

    function totalPreferences(Timeslot memory slot) private pure returns(uint) {
        return slot.upPreferences + slot.downPreferences;
    }
}