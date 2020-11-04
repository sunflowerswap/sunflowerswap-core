pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SunflowerToken.sol";

interface IMigrator {
    // Perform LP token migration from legacy UniswapV2 to SunflowerSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // SunflowerSwap must mint EXACTLY the same amount of SunflowerSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// SunflowerMain is the master of Sunflower. He can make Sunflower and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SFR is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract SunflowerMain is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SFRs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSunflowerPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSunflowerPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SFRs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SFRs distribution occurs.
        uint256 accSunflowerPerShare; // Accumulated SFRs per share, times 1e12. See below.
        // Lock LP, until the end of mining.
        bool lock;
    }

    // The SFR TOKEN!
    SunflowerToken public sunflower;
    // Dev address.
    address public devaddr;
    // SFR tokens created per block.
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigrator public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SFR mining starts.
    uint256 public startBlock;
    uint256 public halfPeriod;
    uint256 public maxSupply;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SunflowerToken _sunflower,
        address _devaddr,
        uint256 _startBlock,
        uint256 _halfPeriod,
        uint256 _maxSupply
    ) public {
        sunflower = _sunflower;
        devaddr = _devaddr;
        startBlock = _startBlock;
        halfPeriod = _halfPeriod;
        maxSupply = _maxSupply;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(block.number < startBlock);
        startBlock = _startBlock;
    }


    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, bool _lock) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSunflowerPerShare: 0,
            lock: _lock
        }));
    }

    // Update the given pool's SFR allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigrator _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    function getBlockRewardNow() public view returns (uint256) {
        return getBlockReward(sunflower.totalSupply());
    }

    // Reduce by 50% per halfPeriod.
    function getBlockReward(uint256 totalSupply) public view returns (uint256) {
        if(totalSupply >= maxSupply) return 0;
        uint256 nth = totalSupply / halfPeriod;
        if(0 == nth)     { return 15625000000000000; }
        else if(1 == nth){ return  7813000000000000; }
        else if(2 == nth){ return  3906000000000000; }
        else if(3 == nth){ return  1953000000000000; }
        else if(4 == nth){ return   977000000000000; }
        else             { return   488000000000000; }
    }

    function getBlockRewards(uint256 from, uint256 to) public view returns (uint256) {
        if(from < startBlock){
            from = startBlock;
        }
        if(from >= to){
            return 0;
        }
        uint256 totalSupply = sunflower.totalSupply();
        if(totalSupply >= maxSupply) return 0;
        uint256 blockReward = getBlockReward(totalSupply);
        uint256 blockGap = to.sub(from);
        uint256 rewards = blockGap.mul(blockReward);
        if(rewards.add(totalSupply) > maxSupply){
            if(totalSupply > maxSupply){
                return 0;
            }else{
                return maxSupply.sub(totalSupply);
            }
        }
        return rewards;
    }

    // View function to see pending SFRs on frontend.
    function pendingSunflower(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSunflowerPerShare = pool.accSunflowerPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blockRewards = getBlockRewards(pool.lastRewardBlock, block.number);
            uint256 sunflowerReward = blockRewards.mul(pool.allocPoint).div(totalAllocPoint);
            accSunflowerPerShare = accSunflowerPerShare.add(sunflowerReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSunflowerPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockRewards = getBlockRewards(pool.lastRewardBlock, block.number);
        uint256 sunflowerReward = blockRewards.mul(pool.allocPoint).div(totalAllocPoint);
        sunflower.mint(devaddr, sunflowerReward.div(10));
        sunflower.mint(address(this), sunflowerReward.mul(9).div(10));
        pool.accSunflowerPerShare = pool.accSunflowerPerShare.add(sunflowerReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to SunflowerMain for SFR allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSunflowerPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeSunflowerTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSunflowerPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from SunflowerMain.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lock == false || pool.lock && sunflower.totalSupply() >= halfPeriod);
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSunflowerPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeSunflowerTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSunflowerPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lock == false || pool.lock && sunflower.totalSupply() >= halfPeriod);
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe sunflower transfer function, just in case if rounding error causes pool to not have enough SFRs.
    function safeSunflowerTransfer(address _to, uint256 _amount) internal {
        uint256 sunflowerBal = sunflower.balanceOf(address(this));
        if (_amount > sunflowerBal) {
            sunflower.transfer(_to, sunflowerBal);
        } else {
            sunflower.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
