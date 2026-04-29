// Metal-specific math constants to avoid duplicate symbol issues
#ifndef METAL_MATH_H
#define METAL_MATH_H

// Define math constants locally to avoid duplicate symbol issues
static const float metal_pi = 3.1415926535897932384626433832795f;
static const float metal_sqrt2 = 1.4142135623730950488016887242097f;
static const float metal_sqrt3 = 1.7320508075688772935274463415059f;

// Override global constants to use local ones
#define pi metal_pi
#define sqrt2 metal_sqrt2
#define sqrt3 metal_sqrt3

#endif // METAL_MATH_H

