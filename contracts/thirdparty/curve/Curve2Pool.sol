pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Curve2Pool {
    int128 constant N_COINS = 2;

    event Transfer(address indexed sender, address indexed receiver, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokenExchange(
        address indexed buyer,
        int128 sold_id,
        uint256 tokens_sold,
        int128 bought_id,
        uint256 tokens_bought
    );
    event AddLiquidity(
        address indexed provider,
        uint256[N_COINS] token_amounts,
        uint256[N_COINS] fees,
        uint256 invariant,
        uint256 token_supply
    );
    event RemoveLiquidity(
        address indexed provider,
        uint256[N_COINS] token_amounts,
        uint256[N_COINS] fees,
        uint256 token_supply
    );
    event RemoveLiquidityOne(address indexed provider, uint256 token_amount, uint256 coin_amount, uint256 token_supply);
    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[N_COINS] token_amounts,
        uint256[N_COINS] fees,
        uint256 invariant,
        uint256 token_supply
    );
    event CommitNewAdmin(uint256 indexed deadline, address indexed admin);

    event NewAdmin(address indexed admin);

    event CommitNewFee(uint256 indexed deadline, uint256 fee, uint256 admin_fee);

    event NewFee(uint256 fee, uint256 admin_fee);

    event RampA(uint256 old_A, uint256 new_A, uint256 initial_time, uint256 future_time);

    event StopRampA(uint256 A, uint256 t);

    uint256 constant PRECISION = 10**18;
    uint256 constant RATE_MULTIPLIER = 1000000000000000000000000000000;
    uint256 constant A_PRECISION = 100;

    uint256 constant FEE_DENOMINATOR = 10**10;

    uint256 constant MAX_ADMIN_FEE = 10 * 10**9;
    uint256 constant MAX_FEE = 5 * 10**9;
    uint256 constant MAX_A = 10**6;
    uint256 constant MAX_A_CHANGE = 10;
    uint256 constant ADMIN_ACTIONS_DELAY = 3 * 86400;
    uint256 constant MIN_RAMP_TIME = 86400;

    address[N_COINS] public coins;
    uint256[N_COINS] public balances;
    uint256 public fee; // fee * 1e10;
    uint256 public admin_fee; // admin_fee * 1e10;

    address public owner;

    uint256 public initial_A;
    uint256 public future_A;
    uint256 public initial_A_time;
    uint256 public future_A_time;

    uint256 public admin_actions_deadline;
    uint256 public transfer_ownership_deadline;
    uint256 public future_fee;
    uint256 public future_admin_fee;
    address public future_owner;

    bool is_killed;
    uint256 kill_deadline;
    uint256 constant KILL_DEADLINE_DT = 2 * 30 * 86400;

    string public name;
    string public symbol;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor(
        address[N_COINS] memory _coins,
        uint256 __A,
        uint256 _fee,
        uint256 _admin_fee,
        string memory _name,
        string memory _symbol
    ) {
        coins = _coins;
        initial_A = __A * A_PRECISION;
        future_A = __A * A_PRECISION;
        fee = _fee;
        admin_fee = _admin_fee;
        owner = msg.sender;

        name = _name;
        symbol = _symbol;

        emit Transfer(address(0), address(this), 0);
    }

    function decimals() external view returns (uint256) {
        return 18;
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
    }

    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool) {
        _transfer(_from, _to, _value);
        uint256 _allowance = allowance[_from][msg.sender];
        if (_allowance != type(uint256).max) {
            allowance[_from][msg.sender] = _allowance - _value;
        }

        return true;
    }

    function approve(address _spender, uint256 _value) external returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    // StableSwap Functionality

    function get_balances() external view returns (uint256[N_COINS] memory) {
        return balances;
    }

    function _A() internal view returns (uint256) {
        uint256 t1 = future_A_time;
        uint256 A1 = future_A;
        if (block.timestamp < t1) {
            uint256 A0 = initial_A;
            uint256 t0 = initial_A_time;
            // Expressions in uint256 cannot have negative numbers, thus "if"
            if (A1 > A0) {
                return A0 + ((A1 - A0) * (block.timestamp - t0)) / (t1 - t0);
            } else {
                return A0 - ((A0 - A1) * (block.timestamp - t0)) / (t1 - t0);
            }
        } else {
            // when t1 == 0 or block.timestamp >= t1
            return A1;
        }
    }

    function A() external view returns (uint256) {
        return _A() / A_PRECISION;
    }

    function A_precise() external view returns (uint256) {
        return _A();
    }

    function _N_COINS_U256() internal pure returns (uint256) {
        return uint256(uint128(N_COINS));
    }

    function _xp_mem(uint256[N_COINS] memory _balances) internal pure returns (uint256[N_COINS] memory result) {
        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            result[i] = (RATE_MULTIPLIER * _balances[i]) / PRECISION;
        }
        return result;
    }

    function get_D(uint256[N_COINS] memory _xp, uint256 _amp) internal pure returns (uint256) {
        uint256 S = 0;
        for (uint256 i = 0; i < _xp.length; i++) {
            S += _xp[i];
        }
        if (S == 0) {
            return 0;
        }
        uint256 D = S;
        uint256 Ann = _amp * _N_COINS_U256();
        for (int128 i = 0; i < 255; i++) {
            uint256 D_P = (((D * D) / _xp[0]) * D) / _xp[1] / (_N_COINS_U256()**2);
            uint256 Dprev = D;
            D =
                (((Ann * S) / A_PRECISION + D_P * _N_COINS_U256()) * D) /
                (((Ann - A_PRECISION) * D) / A_PRECISION + (_N_COINS_U256() + 1) * D_P);
            // Equality with the precision of 1
            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    return D;
                }
            } else {
                if (Dprev - D <= 1) {
                    return D;
                }
            }
        }
        // convergence typically occurs in 4 rounds or less, this should be unreachable!
        // if it does happen the pool is borked and LPs can withdraw via `remove_liquidity`
        revert();
    }

    function get_D_mem(uint256[N_COINS] memory _balances, uint256 _amp) internal pure returns (uint256) {
        uint256[N_COINS] memory xp = _xp_mem(_balances);
        return get_D(xp, _amp);
    }

    function get_virtual_price() external view returns (uint256) {
        uint256 amp = _A();
        uint256[N_COINS] memory xp = _xp_mem(balances);
        uint256 D = get_D(xp, amp);
        return (D * PRECISION) / totalSupply;
    }

    function calc_token_amount(uint256[N_COINS] memory _amounts, bool _is_deposit) external view returns (uint256) {
        // uint256 amp = _A();
        // uint256[N_COINS] memory _balances = balances;
        // uint256 D0 = get_D_mem(balances, amp);
        // for (uint256 i = 0; i < _N_COINS_U256(); i++) {
        //     uint256 amount = _amounts[i];
        //     if (_is_deposit) {
        //         _balances[i] += amount;
        //     } else {
        //         _balances[i] -= amount;
        //     }
        // }
        // uint256 D1 = get_D_mem(_balances, amp);
        // uint256 diff = 0;
        // if (_is_deposit) {
        //     diff = D1 - D0;
        // } else {
        //     diff = D0 - D1;
        // }
        // return (diff * totalSupply) / D0;

        return _amounts[0] + _amounts[1];
    }

    function add_liquidity(uint256[N_COINS] memory _amounts, uint256 _min_mint_amount) public returns (uint256) {
        return add_liquidity(_amounts, _min_mint_amount, msg.sender);
    }

    // @nonreentrant('lock')
    function add_liquidity(
        uint256[N_COINS] memory _amounts,
        uint256 _min_mint_amount,
        address _receiver
    ) internal returns (uint256) {
        require(!is_killed);
        uint256 amp = _A();
        uint256[N_COINS] memory old_balances = balances;

        // Initial invariant
        uint256 D0 = get_D_mem(old_balances, amp);

        uint256 total_supply = totalSupply;
        uint256[N_COINS] memory new_balances = old_balances;
        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                IERC20(coins[i]).transferFrom(msg.sender, address(this), amount);
                new_balances[i] += amount;
            } else {
                require(total_supply != 0); // dev: initial deposit requires all coins
            }
        }

        // Invariant after change
        uint256 D1 = get_D_mem(new_balances, amp);
        require(D1 > D0);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256[N_COINS] memory fees;
        uint256 mint_amount = 0;
        if (total_supply > 0) {
            // Only account for fees if we are not the first to deposit
            uint256 base_fee = (fee * _N_COINS_U256()) / (4 * (_N_COINS_U256() - 1));
            uint256 _admin_fee = admin_fee;
            for (uint256 i = 0; i < _N_COINS_U256(); i++) {
                uint256 ideal_balance = (D1 * old_balances[i]) / D0;
                uint256 difference = 0;
                uint256 new_balance = new_balances[i];
                if (ideal_balance > new_balance) {
                    difference = ideal_balance - new_balance;
                } else {
                    difference = new_balance - ideal_balance;
                }
                fees[i] = (base_fee * difference) / FEE_DENOMINATOR;
                balances[i] = new_balance - ((fees[i] * _admin_fee) / FEE_DENOMINATOR);
                new_balances[i] -= fees[i];
            }
            uint256 D2 = get_D_mem(new_balances, amp);
            mint_amount = (total_supply * (D2 - D0)) / D0;
        } else {
            balances = new_balances;
            mint_amount = D1; // Take the dust if there was any
        }
        require(mint_amount >= _min_mint_amount, "Slippage screwed you");
        // Mint pool tokens
        total_supply += mint_amount;
        balanceOf[_receiver] += mint_amount;
        totalSupply = total_supply;

        emit Transfer(address(0), _receiver, mint_amount);
        emit AddLiquidity(msg.sender, _amounts, fees, D1, total_supply);

        return mint_amount;
    }

    function get_y(
        int128 i,
        int128 j,
        uint256 x,
        uint256[N_COINS] memory xp
    ) internal view returns (uint256) {
        // x in the input is converted to the same price/precision

        require(i != j); // dev: same coin
        require(j >= 0); // dev: j below zero
        require(j < int128(N_COINS)); // dev: j above N_COINS

        // should be unreachable, but good for safety
        require(i >= 0);
        require(i < int128(N_COINS));

        uint256 amp = _A();
        uint256 D = get_D(xp, amp);
        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 y_prev = 0;
        uint256 c = D;
        uint256 Ann = amp * _N_COINS_U256();

        for (int128 _i = 0; _i < N_COINS; _i++) {
            if (_i == i) {
                _x = x;
            } else if (_i != j) {
                _x = xp[uint256(uint128(_i))];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * _N_COINS_U256());
        }

        c = (c * D * A_PRECISION) / (Ann * _N_COINS_U256());
        uint256 b = S_ + (D * A_PRECISION) / Ann; // - D
        uint256 y = D;

        for (uint256 _i = 0; _i < _N_COINS_U256(); _i++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
    }

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256) {
        // uint256[N_COINS] memory xp = _xp_mem(balances);
        // uint256 x = xp[uint256(int256(i))] + ((dx * RATE_MULTIPLIER) / PRECISION);
        // uint256 y = get_y(i, j, x, xp);
        // uint256 dy = xp[uint256(int256(j))] - y - 1;
        // uint256 _fee = (fee * dy) / FEE_DENOMINATOR;
        // return ((dy - _fee) * PRECISION) / RATE_MULTIPLIER;

        return uint128(j);
    }

    // @nonreentrant('lock')
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) public returns (uint256) {
        return exchange(i, j, _dx, _min_dy, msg.sender);
    }

    // @nonreentrant('lock')
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy,
        address _receiver
    ) internal returns (uint256) {
        require(!is_killed); // dev: is killed

        uint256[N_COINS] memory old_balances = balances;
        uint256[N_COINS] memory xp = _xp_mem(old_balances);
        uint256 x = xp[uint256(int256(i))] + (_dx * RATE_MULTIPLIER) / PRECISION;
        uint256 y = get_y(i, j, x, xp);
        uint256 dy = xp[uint256(int256(j))] - y - 1; // -1 just in case there were some rounding errors
        uint256 dy_fee = (dy * fee) / FEE_DENOMINATOR;

        // Convert all to real units
        dy = ((dy - dy_fee) * PRECISION) / RATE_MULTIPLIER;
        require(dy >= _min_dy, "Exchange resulted in fewer coins than expected");
        uint256 dy_admin_fee = (dy_fee * admin_fee) / FEE_DENOMINATOR;
        dy_admin_fee = (dy_admin_fee * PRECISION) / RATE_MULTIPLIER;
        // Change balances exactly in same way as we change actual IERC20 coin amounts
        balances[uint256(int256(i))] = old_balances[uint256(int256(i))] + _dx;
        // When rounding errors happen, we undercharge admin fee in favor of LP
        balances[uint256(int256(j))] = old_balances[uint256(int256(j))] - dy - dy_admin_fee;
        IERC20(coins[uint256(int256(i))]).transferFrom(msg.sender, address(this), _dx);
        IERC20(coins[uint256(int256(j))]).transfer(_receiver, dy);
        emit TokenExchange(msg.sender, i, _dx, j, dy);
        return dy;
    }

    function remove_liquidity(uint256 _burn_amount, uint256[N_COINS] memory _min_amounts)
        public
        returns (uint256[N_COINS] memory)
    {
        return remove_liquidity(_burn_amount, _min_amounts, msg.sender);
    }

    // @nonreentrant('lock')
    function remove_liquidity(
        uint256 _burn_amount,
        uint256[N_COINS] memory _min_amounts,
        address _receiver
    ) internal returns (uint256[N_COINS] memory) {
        uint256 total_supply = totalSupply;
        uint256[N_COINS] memory amounts;

        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            uint256 old_balance = balances[i];
            uint256 value = (old_balance * _burn_amount) / total_supply;
            require(value >= _min_amounts[i], "Withdrawal resulted in fewer coins than expected");
            balances[i] = old_balance - value;
            amounts[i] = value;
            IERC20(coins[i]).transfer(_receiver, value);
        }

        total_supply -= _burn_amount;
        balanceOf[msg.sender] -= _burn_amount;
        totalSupply = total_supply;
        emit Transfer(msg.sender, address(0), _burn_amount);

        emit RemoveLiquidity(msg.sender, amounts, _min_amounts, total_supply);

        return amounts;
    }

    function remove_liquidity_imbalance(uint256[N_COINS] memory _amounts, uint256 _max_burn_amount)
        public
        returns (uint256)
    {
        return remove_liquidity_imbalance(_amounts, _max_burn_amount, msg.sender);
    }

    // @nonreentrant('lock')
    function remove_liquidity_imbalance(
        uint256[N_COINS] memory _amounts,
        uint256 _max_burn_amount,
        address _receiver
    ) internal returns (uint256) {
        require(!is_killed); // dev: is killed

        uint256 amp = _A();
        uint256[N_COINS] memory old_balances = balances;
        uint256 D0 = get_D_mem(old_balances, amp);

        uint256[N_COINS] memory new_balances = old_balances;
        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            uint256 amount = _amounts[i];
            if (amount != 0) {
                new_balances[i] -= amount;
                IERC20(coins[i]).transfer(_receiver, amount);
            }
        }
        uint256 D1 = get_D_mem(new_balances, amp);
        uint256 base_fee = (fee * _N_COINS_U256()) / (4 * (_N_COINS_U256() - 1));
        uint256[N_COINS] memory fees;
        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            uint256 new_balance = new_balances[i];
            uint256 ideal_balance = (D1 * old_balances[i]) / D0;
            uint256 difference = 0;
            if (ideal_balance > new_balance) {
                difference = ideal_balance - new_balance;
            } else {
                difference = new_balance - ideal_balance;
            }
            fees[i] = (base_fee * difference) / FEE_DENOMINATOR;
            balances[i] = new_balance - ((fees[i] * admin_fee) / FEE_DENOMINATOR);
            new_balances[i] -= fees[i];
        }
        uint256 D2 = get_D_mem(new_balances, amp);

        uint256 total_supply = totalSupply;
        uint256 burn_amount = (((D0 - D2) * total_supply) / D0) + 1;
        require(burn_amount > 1); // dev: zero tokens burned
        require(burn_amount <= _max_burn_amount, "Slippage screwed you");

        total_supply -= burn_amount;
        totalSupply = total_supply;
        balanceOf[msg.sender] -= burn_amount;
        emit Transfer(msg.sender, address(0), burn_amount);
        emit RemoveLiquidityImbalance(msg.sender, _amounts, fees, D1, total_supply);

        return burn_amount;
    }

    function get_y_D(
        uint256 A_,
        int128 i,
        uint256[N_COINS] memory xp,
        uint256 D
    ) internal pure returns (uint256) {
        require(i >= 0); // dev: i below zero
        require(i < N_COINS); // dev: i above N_COINS

        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 y_prev = 0;
        uint256 c = D;
        uint256 Ann = A_ * _N_COINS_U256();

        for (int128 _i = 0; _i < N_COINS; _i++) {
            if (_i != i) {
                _x = xp[uint256(uint128(_i))];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * _N_COINS_U256());
        }

        c = (c * D * A_PRECISION) / (Ann * _N_COINS_U256());
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 y = D;

        for (uint256 _i = 0; _i < _N_COINS_U256(); _i++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                } else {
                    if (y_prev - y <= 1) {
                        return y;
                    }
                }
            }
        }
        revert();
    }

    // @view

    function _calc_withdraw_one_coin(uint256 _burn_amount, int128 i)
        internal
        view
        returns (uint256[N_COINS] memory result)
    {
        uint256 amp = _A();
        uint256[N_COINS] memory xp = _xp_mem(balances);
        uint256 D0 = get_D(xp, amp);

        uint256 total_supply = totalSupply;
        uint256 D1 = D0 - (_burn_amount * D0) / total_supply;
        uint256 new_y = get_y_D(amp, i, xp, D1);

        uint256 base_fee = (fee * _N_COINS_U256()) / (4 * (_N_COINS_U256() - 1));
        uint256[N_COINS] memory xp_reduced;

        for (int128 j = 0; j < N_COINS; j++) {
            uint256 dx_expected = 0;
            uint256 xp_j = xp[uint256(uint128(j))];
            if (j == i) {
                dx_expected = (xp_j * D1) / D0 - new_y;
            } else {
                dx_expected = xp_j - (xp_j * D1) / D0;
            }
            xp_reduced[uint256(uint128(j))] = xp_j - (base_fee * dx_expected) / FEE_DENOMINATOR;
        }

        uint256 dy = xp_reduced[uint256(uint128(i))] - get_y_D(amp, i, xp_reduced, D1);
        uint256 dy_0 = ((xp[uint256(uint128(i))] - new_y) * PRECISION) / RATE_MULTIPLIER; // w/o fees
        dy = ((dy - 1) * PRECISION) / RATE_MULTIPLIER; // Withdraw less to account for rounding errors

        result[0] = dy;
        result[1] = dy_0 - dy;
    }

    function calc_withdraw_one_coin(uint256 _burn_amount, int128 i) external view returns (uint256) {
        return _calc_withdraw_one_coin(_burn_amount, i)[0];
    }

    // @nonreentrant('lock')
    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        int128 i,
        uint256 _min_received,
        address _receiver
    ) public returns (uint256) {
        require(!is_killed); // dev: is killed

        uint256[N_COINS] memory dy = _calc_withdraw_one_coin(_burn_amount, i);
        require(dy[0] >= _min_received, "Not enough coins removed");

        balances[uint256(uint128(i))] -= (dy[0] + (dy[1] * admin_fee) / FEE_DENOMINATOR);
        uint256 total_supply = totalSupply - _burn_amount;
        totalSupply = total_supply;
        balanceOf[msg.sender] -= _burn_amount;
        emit Transfer(msg.sender, address(0), _burn_amount);

        IERC20(coins[uint256(uint128(i))]).transfer(_receiver, dy[0]);

        emit RemoveLiquidityOne(msg.sender, _burn_amount, dy[0], total_supply);

        return dy[0];
    }

    function ramp_A(uint256 _future_A, uint256 _future_time) external {
        require(msg.sender == owner); // dev: only owner
        require(block.timestamp >= initial_A_time + MIN_RAMP_TIME);
        require(_future_time >= block.timestamp + MIN_RAMP_TIME); // dev: insufficient time

        uint256 _initial_A = _A();
        uint256 _future_A_p = _future_A * A_PRECISION;

        require(_future_A > 0 && _future_A < MAX_A);
        if (_future_A_p < _initial_A) {
            require(_future_A_p * MAX_A_CHANGE >= _initial_A);
        } else {
            require(_future_A_p <= _initial_A * MAX_A_CHANGE);
        }

        initial_A = _initial_A;
        future_A = _future_A_p;
        initial_A_time = block.timestamp;
        future_A_time = _future_time;

        emit RampA(_initial_A, _future_A_p, block.timestamp, _future_time);
    }

    function stop_ramp_A() external {
        require(msg.sender == owner); // dev: only owner

        uint256 current_A = _A();
        initial_A = current_A;
        future_A = current_A;
        initial_A_time = block.timestamp;
        future_A_time = block.timestamp;
        // now (block.timestamp < t1) is always false, so we return saved A

        emit StopRampA(current_A, block.timestamp);
    }

    function commit_new_fee(uint256 _new_fee, uint256 _new_admin_fee) external {
        require(msg.sender == owner); // dev: only owner
        require(admin_actions_deadline == 0); // dev: active action
        require(_new_fee <= MAX_FEE); // dev: fee exceeds maximum
        require(_new_admin_fee <= MAX_ADMIN_FEE); // dev: admin fee exceeds maximum

        uint256 deadline = block.timestamp + ADMIN_ACTIONS_DELAY;
        admin_actions_deadline = deadline;
        future_fee = _new_fee;
        future_admin_fee = _new_admin_fee;

        emit CommitNewFee(deadline, _new_fee, _new_admin_fee);
    }

    function apply_new_fee() external {
        require(msg.sender == owner); // dev: only owner
        require(block.timestamp >= admin_actions_deadline); // dev: insufficient time
        require(admin_actions_deadline != 0); // dev: no active action

        admin_actions_deadline = 0;
        uint256 fee_ = future_fee;
        uint256 admin_fee_ = future_admin_fee;
        fee = fee_;
        admin_fee = admin_fee_;

        emit NewFee(fee, admin_fee);
    }

    function revert_new_parameters() external {
        require(msg.sender == owner); // dev: only owner

        admin_actions_deadline = 0;
    }

    function commit_transfer_ownership(address _owner) external {
        require(msg.sender == owner); // dev: only owner
        require(transfer_ownership_deadline == 0); // dev: active transfer

        uint256 deadline = block.timestamp + ADMIN_ACTIONS_DELAY;
        transfer_ownership_deadline = deadline;
        future_owner = _owner;

        emit CommitNewAdmin(deadline, _owner);
    }

    function apply_transfer_ownership() external {
        require(msg.sender == owner); // dev: only owner
        require(block.timestamp >= transfer_ownership_deadline); // dev: insufficient time
        require(transfer_ownership_deadline != 0); // dev: no active transfer

        transfer_ownership_deadline = 0;
        owner = future_owner;

        emit NewAdmin(owner);
    }

    function revert_transfer_ownership() external {
        require(msg.sender == owner); // dev: only owner

        transfer_ownership_deadline = 0;
    }

    function admin_balances(uint256 i) external view returns (uint256) {
        return IERC20(coins[i]).balanceOf(address(this)) - balances[i];
    }

    function withdraw_admin_fees() external {
        require(msg.sender == owner); // dev: only owner

        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            address coin = coins[i];
            uint256 fees = IERC20(coin).balanceOf(address(this)) - balances[i];
            IERC20(coin).transfer(msg.sender, fees);
        }
    }

    function donate_admin_fees() external {
        require(msg.sender == owner); // dev: only owner
        for (uint256 i = 0; i < _N_COINS_U256(); i++) {
            balances[i] = IERC20(coins[i]).balanceOf(address(this));
        }
    }

    function kill_me() external {
        require(msg.sender == owner); // dev: only owner
        require(kill_deadline > block.timestamp); // dev: deadline has passed
        is_killed = true;
    }

    function unkill_me() external {
        require(msg.sender == owner); // dev: only owner
        is_killed = false;
    }
}
