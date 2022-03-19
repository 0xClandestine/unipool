import math

def scaleK(x, y, tk):

    k = x*y

    rootK = math.sqrt(k)
    rootTk = math.sqrt(tk)

    x *= rootTk / rootK
    y *= rootTk / rootK

    # assert(x * y == tk)

    print(f'x := {x}')
    print(f'y := {y}')
    print(f'k {x*y} := tk {tk}')

    return rootTk / rootK

# print(scaleK(1000e18, 100e18, 1e18));

# test variables

amountIn = 100e18
x = 1000e18
y = 1000e18

# calculate adjusted amount out, and adjusted amount out

scaler = scaleK(x, y, x * y * 10)
amountOut = y * amountIn / (x + amountIn)
amountOut2 = (y * scaler * amountIn) / (x * scaler + amountIn)

print(f"""
no slippage amount out: {amountIn * x / y / 1e18}
unadjusted amount out: {round(amountOut / 1e18, 2)}

adjusted amount out: {amountOut2 / 1e18}
""")

# test price 

x2 = x + amountIn;
y2 = y - amountOut2;

# print(x2 * y2)

scaler = scaleK(x2, y2, x2 * y2 * 10)
amountOut3 = (y2 * scaler * amountIn) / (x2 * scaler + amountIn)
print(f"adjusted amount out, trade 2: {amountOut3/ 1e18}")