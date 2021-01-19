// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/Math.sol";
import "https://github.com/OpenZeppelin/openzeppelin-sdk/blob/master/packages/lib/contracts/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

contract StakePool is Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public depositToken;
    address public feeTo;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function initialize(address _token, address _feeTo) public initializer {
        depositToken = IERC20(_token);
        feeTo = address(_feeTo);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function _stake(uint256 amount) internal {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _withdraw(uint256 amount) internal {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        depositToken.safeTransfer(msg.sender, amount);
    }

    // Update feeTo address by the previous feeTo.
    function feeToUpdate(address _feeTo) public {
        require(msg.sender == feeTo, "feeTo: wut?");
        feeTo = _feeTo;
    }
}

/**
 * Yield Token will be halved at each period.
 */

 contract Farming is StakePool {
     // Yield Token as a reward for stakers
     IERC20 public rewardToken;

     // Halving period in seconds, should be defined as 1 week
     uint256 public halvingPeriod = 604800;
     // Total reward in 18 decimal
     uint256 public totalreward;
     // Starting timestamp for LaunchField
     uint256 public starttime;
     // The timestamp when stakers should be allowed to withdraw
     uint256 public stakingtime;
     uint256 public eraPeriod = 0;
     uint256 public rewardRate = 0;
     uint256 public lastUpdateTime;
     uint256 public rewardPerTokenStored;
     uint256 public totalRewards = 0;

     mapping(address => uint256) public userRewardPerTokenPaid;
     mapping(address => uint256) public rewards;

     event RewardAdded(uint256 reward);
     event Staked(address indexed user, uint256 amount);
     event Withdrawn(address indexed user, uint256 amount);
     event RewardPaid(address indexed user, uint256 reward);

     modifier updateReward(address account) {
         rewardPerTokenStored = rewardPerToken();
         lastUpdateTime = lastTimeRewardApplicable();
         if (account != address(0)) {
             rewards[account] = earned(account);
             userRewardPerTokenPaid[account] = rewardPerTokenStored;
         }
         _;
     }

     constructor(address _depositToken, address _rewardToken, uint256 _totalreward, uint256 _starttime, uint256 _stakingtime) public {
         super.initialize(_depositToken, msg.sender);
         rewardToken = IERC20(_rewardToken);

         starttime = _starttime;
         stakingtime = _stakingtime;
         notifyRewardAmount(_totalreward.mul(50).div(100));
     }

     function lastTimeRewardApplicable() public view returns (uint256) {
         return Math.min(block.timestamp, eraPeriod);
     }

     function rewardPerToken() public view returns (uint256) {
         if (totalSupply() == 0) {
             return rewardPerTokenStored;
         }
         return
             rewardPerTokenStored.add(
                 lastTimeRewardApplicable()
                     .sub(lastUpdateTime)
                     .mul(rewardRate)
                     .mul(1e18)
                     .div(totalSupply())
             );
     }

     function earned(address account) public view returns (uint256) {
         return
             balanceOf(account)
                 .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                 .div(1e18)
                 .add(rewards[account]);
     }

     function stake(uint256 amount) public updateReward(msg.sender) checkhalve checkStart{
         require(amount > 0, "ERROR: Cannot stake 0 Token");
         super._stake(amount);
         emit Staked(msg.sender, amount);
     }

     function withdraw(uint256 amount) public updateReward(msg.sender) checkhalve checkStart stakingTime{
        require(amount > 0, "ERROR: Cannot withdraw 0");
        super._withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external stakingTime{
        withdraw(balanceOf(msg.sender));
        _getRewardInternal();
    }

     function getReward() public updateReward(msg.sender) checkhalve checkStart stakingTime{
         uint256 reward = earned(msg.sender);
         uint256 feeamount = reward.div(20); // 5%
         uint256 finalamount = (reward - feeamount);
         if (reward > 0) {
             rewards[msg.sender] = 0;
             rewardToken.safeTransfer(msg.sender, finalamount);
             rewardToken.safeTransfer(feeTo, feeamount);
             emit RewardPaid(msg.sender, finalamount);
             emit RewardPaid(feeTo, feeamount);
             totalRewards = totalRewards.add(reward);
         }
     }

     function _getRewardInternal() internal updateReward(msg.sender) checkhalve checkStart{
         uint256 reward = earned(msg.sender);
         uint256 feeamount = reward.div(20); // 5%
         uint256 finalamount = (reward - feeamount);
         if (reward > 0) {
             rewards[msg.sender] = 0;
             rewardToken.safeTransfer(msg.sender, finalamount);
             rewardToken.safeTransfer(feeTo, feeamount);
             emit RewardPaid(msg.sender, finalamount);
             emit RewardPaid(feeTo, feeamount);
             totalRewards = totalRewards.add(reward);
         }
     }

     modifier checkhalve(){
         if (block.timestamp >= eraPeriod) {
             totalreward = totalreward.mul(50).div(100);

             rewardRate = totalreward.div(halvingPeriod);
             eraPeriod = block.timestamp.add(halvingPeriod);
             emit RewardAdded(totalreward);
         }
         _;
     }

     modifier checkStart(){
         require(block.timestamp > starttime,"ERROR: Not start");
         _;
     }

     modifier stakingTime(){
         require(block.timestamp >= stakingtime,"ERROR: Withdrawals not allowed yet");
         _;
     }

     function notifyRewardAmount(uint256 reward)
         internal
         updateReward(address(0))
     {
         if (block.timestamp >= eraPeriod) {
             rewardRate = reward.div(halvingPeriod);
         } else {
             uint256 remaining = eraPeriod.sub(block.timestamp);
             uint256 leftover = remaining.mul(rewardRate);
             rewardRate = reward.add(leftover).div(halvingPeriod);
         }
         totalreward = reward;
         lastUpdateTime = block.timestamp;
         eraPeriod = block.timestamp.add(halvingPeriod);
         emit RewardAdded(reward);
     }
 }
