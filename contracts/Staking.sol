//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";

struct PoolStaker {
        uint256 amount; // The tokens quantity the user has staked.
        uint256 stakedTime; //the time at tokens staked
    }
  
library IterableMapping {
    // Iterable mapping from address to uint;
  
    struct Map {
        address[] keys;
        mapping(address => PoolStaker) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
        uint8 key;
    }
    function get(Map storage map, address key) internal view returns (PoolStaker memory) {
        return map.values[key];
    }

    function getKeyAtIndex(Map storage map, uint256 index)
        internal
        view
        returns (address)
    {
        return map.keys[index];
    }

    function size(Map storage map) internal view returns (uint256) {
        return map.keys.length;
    }

    function set(Map storage map, address key, PoolStaker memory val) internal {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(Map storage map, address key) internal {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint256 index = map.indexOf[key];
        address lastKey = map.keys[map.keys.length - 1];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}

contract StakingManagerV3 is OwnableUpgradeable,  ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20; // Wrappers around ERC20 operations that throw on failure
    // for oracle timer
    uint private oraclePayment;
    address private oracle;
    bytes32 private jobId;

    using IterableMapping for IterableMapping.Map;
    IterableMapping.Map public poolStakers;
    IERC20 public stakeToken; // Token to be staked and rewarded
    IERC20 public rewardToken;
    uint256 public tokensStaked; // Total tokens staked
    uint256 public currentEpochReward;
    uint256 private lastRewardedTime; // Last block number the user had their rewards calculated

    uint256 public currentEpochStartTime;
    uint256 public currentEpochEndTime;
    
    // two dimension mappin
    struct UserInfoInEpoch {
        uint256 harvestedReward;
        uint256 lockedReward;
    }

    uint16 public epochId;
    mapping(uint16 => mapping(address => UserInfoInEpoch)) public epochLog;

    struct EpochInfo {
        uint256 startTime;
        uint256 endTime;
    }

    mapping(uint16 => EpochInfo) epochInfos;
    //  staker address => PoolStaker
   // mapping(address => PoolStaker) public poolStakers;

    bool resetFlag;


    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event HarvestRewards(address indexed user, uint256 amount);
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier validEpoch(uint16 _epochId) {
        require(_epochId <= epochId, "Invalid Epoch");
        _;
    }

    function initialize(
        address _stakeTokenAddress,
        address _rewardTokenAddress
    ) public initializer {
        __Ownable_init_unchained(msg.sender);
         __ReentrancyGuard_init_unchained();
        epochId = 0;
        rewardToken = IERC20(_rewardTokenAddress);
        stakeToken = IERC20(_stakeTokenAddress);
        
    }
    /**
     * @dev Deposit tokens to the pool
     */
    function deposit(uint256 _amount) external {

        require(_amount > 0, "Deposit amount can't be zero");

        PoolStaker memory staker = poolStakers.get(msg.sender);
        staker.amount += _amount;
        if(staker.stakedTime == 0){
            staker.stakedTime = block.timestamp;
        }
        tokensStaked += _amount;
        poolStakers.set(msg.sender, staker);
        emit Deposit(msg.sender, _amount);
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev unstake all tokens from existing pool
     */
    function unstake() external nonReentrant {
        PoolStaker memory staker = poolStakers.get(msg.sender);
        uint256 amount = staker.amount;

        require(amount > 0, "Withdraw amount can't be zero");

        for(uint16 i = 0; i < epochId; i++){
            if(epochInfos[i].endTime > staker.stakedTime && staker.stakedTime != 0) {
                rewardToken.safeTransfer(msg.sender, epochLog[i][msg.sender].lockedReward);
                epochLog[i][msg.sender].lockedReward = 0;
            }
        }
        //delete staker
        poolStakers.remove(msg.sender);

        // Update pool
        tokensStaked -= amount;

        // Withdraw tokens
        emit Withdraw(msg.sender, amount);
        stakeToken.safeTransfer(msg.sender, amount);
    }

    function depositReward(uint256 _amount) external onlyOwner {
        require(_amount > 0, "amount can't be zero");
        bool success = rewardToken.transferFrom(owner(), address(this), _amount);
        require(success, "transferFrom failed");
        currentEpochReward += _amount;
    }
   
    /**
     *@dev To get the number of rewards that user can get
     */
    function getRewards(address _user) public view returns (uint256) {
        if (tokensStaked == 0) {
            return 0;
        }
        uint256 timeTick = block.timestamp;
        require(timeTick > currentEpochStartTime && timeTick < currentEpochEndTime, "Only be able to see the reward on epoch");
        PoolStaker memory staker = poolStakers.get(_user);
        return  staker.amount * (currentEpochEndTime - timeTick) / tokensStaked * currentEpochReward;
    }
      /**
     *@dev To get the number of rewards that user get on specific epoch
     */
     function seeReward(uint16 _epoch) validEpoch(_epoch) public view returns (uint256) {
        UserInfoInEpoch storage info = epochLog[_epoch][msg.sender];
        require(info.lockedReward > 0, "No reward");
        return info.lockedReward;
    }


    function startEpoch(uint256 _startTime, uint256 _endTime, uint256 _rewardAmount) external onlyOwner {
        require(_startTime > currentEpochEndTime, "Epoch is past");
        require(_endTime > _startTime, "End time must be bigger than start time");
        require(_rewardAmount > 0, "amount can't be zero");
        bool success = rewardToken.transferFrom(owner(), address(this), _rewardAmount);
        require(success, "transferFrom failed");
        currentEpochReward += _rewardAmount;
        currentEpochStartTime = _startTime;
        currentEpochEndTime = _endTime;
        epochInfos[epochId] = EpochInfo(_startTime, _endTime);
        epochId++;
    }


    function setStakeToken(address _stakeToken) external onlyOwner {
        stakeToken = IERC20(_stakeToken);
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = IERC20(_rewardToken);
    }

    function withdrawStakeToken(uint256 _amount) external onlyOwner {
        stakeToken.safeTransfer(owner(), _amount);
    }

     function withdrawRewardToken(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(owner(), _amount);
    }

    function distribute() external onlyOwner {
        require(block.timestamp > currentEpochEndTime, "The Epoch didn't end");
        
        uint256 counts = poolStakers.keys.length;
        for (uint256 i = 0; i < counts; i++) {
            
            address key = poolStakers.getKeyAtIndex(i);
            PoolStaker memory staker = poolStakers.get(key);
            
            if(currentEpochStartTime < staker.stakedTime && staker.stakedTime < currentEpochEndTime) {
                uint256 duration = currentEpochEndTime - currentEpochStartTime;
                UserInfoInEpoch storage userInfo = epochLog[epochId][key];
                userInfo.lockedReward += staker.amount  * currentEpochReward * (currentEpochEndTime - staker.stakedTime) / ( tokensStaked * duration) ;
                poolStakers.set(key, staker);
            } else if (staker.amount > 0) {
                UserInfoInEpoch storage userInfo = epochLog[epochId][key];
                userInfo.lockedReward += staker.amount / tokensStaked * currentEpochReward;
                poolStakers.set(key, staker);
            }
        }
    }

    function claim(uint16 _epoch) validEpoch(_epoch)  external nonReentrant{
        UserInfoInEpoch storage info = epochLog[_epoch][msg.sender];
        uint256 reward = info.lockedReward;
        require( reward > 0, "No reward");
        rewardToken.transfer(msg.sender, reward);
        info.lockedReward = 0;
        emit HarvestRewards(msg.sender, reward);
    }

    function deleteEpoch(uint16 _epoch) validEpoch(_epoch) external onlyOwner {
         uint256 counts = poolStakers.keys.length;
         for (uint256 i = 0; i < counts; i++) {
            address stakerAddress = poolStakers.getKeyAtIndex(i);
            UserInfoInEpoch memory userInfo = epochLog[_epoch][stakerAddress];
            rewardToken.safeTransfer(stakerAddress, userInfo.lockedReward);
            delete epochLog[_epoch][stakerAddress];
        }
    }
}

