// SPDX-License-Identifier: MIT
import "./lptoken.sol";
import "./ILPToken.sol";

pragma solidity ^0.8.17;

contract CPAMM {



    address [] public lpTokenAddressList;



    mapping(address => uint) public reserve0;
    mapping(address => uint) public reserve1;

    //检索lptoken
    mapping(address => mapping(address => address)) public findLpToken;



    function createPair(address addrToken0, address addrToken1) public returns(address){
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1
            )
        );
        new LPToken{
            salt : bytes32(_salt)
        }
        ();
        address lptokenAddr = getAddress(getBytecode(),_salt);

         //检索lptoken
        lpTokenAddressList.push(lptokenAddr);
        findLpToken[addrToken0][addrToken1] = lptokenAddr;
        findLpToken[addrToken1][addrToken0] = lptokenAddr;

        return lptokenAddr;
    }

    function lptokenTotalSupply(address _token0, address _token1, address user) public view returns(uint)
    {
        ILPToken lptoken;
        lptoken = ILPToken(findLpToken[_token0][_token1]);
        uint totalSupply = lptoken.balanceOf(user);
        return totalSupply;
    }
    function getAddress(bytes memory bytecode, bytes32 _salt)
        public
        view
        returns(address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), _salt, keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    function getBytecode() public pure returns(bytes memory) {
        bytes memory bytecode = type(LPToken).creationCode;
        return bytecode;
    }



    function _update(address _token0, address _token1, uint _reserve0, uint _reserve1) private {
        reserve0[_token0] = _reserve0;
        reserve1[_token1] = _reserve1;
    }


    function swap(address _tokenIn, address _tokenOut, uint _amountIn) external returns (uint amountOut) {
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);





        bool isToken0 = _tokenIn < _tokenOut;
        (IERC20 tokenIn, IERC20 tokenOut, uint reserveIn, uint reserveOut) = isToken0
            ? (IERC20(_tokenIn), IERC20(_tokenOut), reserve0[_tokenIn], reserve1[_tokenOut])
            : (IERC20(_tokenOut), IERC20(_tokenIn), reserve1[_tokenOut], reserve0[_tokenIn]);

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);

        /*
        How much dy for dx?
        xy = k
        (交易后)(x + dx)(y - dy) = k 对于交易所的视角 k = xy(交易前) y -dy = xy/(x + dx) // dy = y - xy/(x + dx)
        y - dy = k / (x + dx)           // = (y(x + dx)  - xy) / (x + dx) = ydx  / (x + dx)
        y - k / (x + dx) = dy
        y - xy / (x + dx) = dy
        (yx + ydx - xy) / (x + dx) = dy
        ydx / (x + dx) = dy
        */
        // 0.3% fee
        uint amountInWithFee = (_amountIn * 997) / 1000;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        //(输出的token总数量 * 输入的token数量) / (输入token的总数量 + 输入的token数量)
        // 比如有1000输出token，200输入token，用户输入50token，
        //则 (1000 * 50)/(200 + 50) = 200 
        //原价1000 ：200 是 5 ：1
        //输出对比是 200 ：50 是 4 ：1
        //出现这个结果就是滑点问题

        /*
        比如100000token1，20000token0，用户输入50token0
        则(100000 * 50) / (20000 + 50) = 249.376558603
        原价1000 ：200 是 5 ：1
        输出对比是 249.376558603 ：50 是接近 5 ：1
        池子越大用户的购买的比例占池子比例越低，则滑点越低
        */

        tokenOut.transfer(msg.sender, amountOut);

        _update(_tokenIn, _tokenOut, tokenIn.balanceOf(address(this)), tokenOut.balanceOf(address(this)));
    }
    //test function 




    /*
        添加流动性得到的lptoken
    lptoken = （token0 * token1 ）开根号
    存在tokenA 和 tokenB
    我们第一次添加了100A 和 400 B
    Lptoken = sqrt（100 * 400）= 200
    二次添加后的数量 token0*token1 开根号
    撤回流动性
    撤回的token0和token1 =

    token0 = 撤回的lptoken/总lptoken*reverse0

    token1 = 撤回的lptoken/总lptoken*reverse1
    */
    function addLiquidity(address _token0, address _token1, uint _amount0, uint _amount1) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        require(_amount0 > 0 && _amount1 > 0 ,"require _amount0 > 0 && _amount1 >0");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        /*
        How much dx, dy to add?
        xy = k
        (x + dx)(y + dy) = k'
        No price change, before and after adding liquidity
        x / y = (x + dx) / (y + dy)
        x(y + dy) = y(x + dx)
        x * dy = y * dx
        x / y = dx / dy
        dy = y / x * dx
        */
        //问题：
        /*
        如果项目方撤出所有流动性后会存在问题
        1.添加流动性按照比例 0/0 会报错

        解决方案：
        每次添加至少n个token
        且remove流动性至少保留n给在amm里面

        */
        if (findLpToken[_token1][_token0] != address(0)) {
            require(reserve0[_token0] * _amount1 == reserve1[_token1] * _amount0, "x / y != dx / dy");
            //必须保持等比例添加，添加后k值会改变
        }

        /*
        How much shares to mint?
        f(x, y) = value of liquidity
        We will define f(x, y) = sqrt(xy)
        L0 = f(x, y)
        L1 = f(x + dx, y + dy)
        T = total shares
        s = shares to mint
        Total shares should increase proportional to increase in liquidity
        L1 / L0 = (T + s) / T
        L1 * T = L0 * (T + s)
        式子A
        A:(L1 - L0) * T / L0 = s 
        */

        /*
        Claim
        其实就是 dlp/lp = dx/x = dy /y
        式子B
        B:(L1 - L0) / L0 = dx / x = dy / y 则 dx/x*T 或 dy/y *T
        Proof
        --- Equation 1 ---
        (L1 - L0) / L0 = (sqrt((x + dx)(y + dy)) - sqrt(xy)) / sqrt(xy)
        
        dx / dy = x / y so replace dy = dx * y / x
        --- Equation 2 ---
        Equation 1 = (sqrt(xy + 2ydx + dx^2 * y / x) - sqrt(xy)) / sqrt(xy)
        Multiply by sqrt(x) / sqrt(x)
        Equation 2 = (sqrt(x^2y + 2xydx + dx^2 * y) - sqrt(x^2y)) / sqrt(x^2y)
                   = (sqrt(y)(sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(y)sqrt(x^2))
        
        sqrt(y) on top and bottom cancels out
        --- Equation 3 ---
        Equation 2 = (sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(x^2)
        = (sqrt((x + dx)^2) - sqrt(x^2)) / sqrt(x^2)  
        = ((x + dx) - x) / x
        = dx / x
        Since dx / dy = x / y,
        dx / x = dy / y
        Finally
        (L1 - L0) / L0 = dx / x = dy / y
        */
        if (findLpToken[_token1][_token0] == address(0)) {
            //当lptoken = 0时，创建lptoken
            shares = _sqrt(_amount0 * _amount1);
            createPair(_token0,_token1);
            address lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            
        } else {
            address lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            shares = _min(
                (_amount0 * lptoken.totalSupply()) / reserve0[_token0],
                (_amount1 * lptoken.totalSupply()) / reserve1[_token1]
            );
            //获取lptoken地址
        }
        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);
        

        _update(_token0, _token1,token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }
    /*
        撤回流动性
    撤回的token0和token1 =

    token0 = 撤回的lptoken/总lptoken*reverse0

    token1 = 撤回的lptoken/总lptoken*reverse1
    */
    function removeLiquidity(
        address _token0,
        address _token1,
        uint _shares
    ) external returns (uint amount0, uint amount1) {
        /*
        Claim
        dx, dy = amount of liquidity to remove
        dx = s / T * x
        dy = s / T * y
        Proof
        Let's find dx, dy such that
        v / L = s / T
        
        where
        v = f(dx, dy) = sqrt(dxdy)
        L = total liquidity = sqrt(xy)
        s = shares
        T = total supply
        --- Equation 1 ---
        v = s / T * L
        sqrt(dxdy) = s / T * sqrt(xy)
        Amount of liquidity to remove must not change price so 
        dx / dy = x / y
        replace dy = dx * y / x
        sqrt(dxdy) = sqrt(dx * dx * y / x) = dx * sqrt(y / x)
        Divide both sides of Equation 1 with sqrt(y / x)
        dx = s / T * sqrt(xy) / sqrt(y / x)
           = s / T * sqrt(x^2) = s / T * x
        Likewise
        dy = s / T * y
        */

        // bal0 >= reserve0
        // bal1 >= reserve1
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        address lptokenAddr = findLpToken[_token0][_token1];
        lptoken = ILPToken(lptokenAddr);
        uint bal0 = token0.balanceOf(address(this));
        uint bal1 = token1.balanceOf(address(this));

        amount0 = (_shares * bal0) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * bal1) / lptoken.totalSupply();
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        lptoken.burn(msg.sender, _shares);
        _update(_token0, _token1,bal0 - amount0, bal1 - amount1);

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}

