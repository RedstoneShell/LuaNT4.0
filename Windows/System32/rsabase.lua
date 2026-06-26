-- rsabase.lua - CryptoAPI Base Provider для LuaNT
-- (C) RedstoneShell 2026 / Fixed & Optimized for OpenComputers

local crypto = {}

-- Helpers
local PI = {
    0xd9, 0x78, 0xf9, 0xc4, 0x19, 0xdd, 0xb5, 0xed, 0x28, 0xe9, 0xfd, 0x79, 0x4a, 0xa0, 0xd8, 0x9d,
    0xc6, 0x7e, 0x37, 0x83, 0x2b, 0x76, 0x53, 0x8e, 0x62, 0x4c, 0x64, 0x88, 0x44, 0x8b, 0xfb, 0xa2,
    0x17, 0x9a, 0x59, 0xf5, 0x87, 0xb3, 0x4f, 0x13, 0x61, 0x45, 0x6d, 0x8d, 0x09, 0x81, 0x7d, 0x32,
    0xbd, 0x8f, 0x40, 0xeb, 0x86, 0xb7, 0x7b, 0x0b, 0xf0, 0x95, 0x21, 0x22, 0x5c, 0x6b, 0x4e, 0x82,
    0x54, 0xd6, 0x65, 0x93, 0xce, 0x60, 0xb2, 0x1c, 0x73, 0x56, 0xc0, 0x14, 0xa7, 0x8c, 0xf1, 0xdc,
    0x12, 0x75, 0xca, 0x1f, 0x3b, 0xbe, 0xe4, 0x5a, 0xad, 0xae, 0x90, 0x37, 0x8a, 0xc7, 0xdc, 0x3e,
    0x1d, 0x8a, 0x2f, 0x11, 0xb1, 0x85, 0x3a, 0x42, 0x69, 0x96, 0xa4, 0xfa, 0xbe, 0x2c, 0x72, 0x8c,
    0xcd, 0x6c, 0xd8, 0x0e, 0x3c, 0x15, 0xf2, 0x05, 0xcc, 0x45, 0xab, 0x34, 0x4b, 0x80, 0x98, 0x7b
}

local IP = {
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7
}
local IP_INV = {
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25
}
local E = {
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1
}
local P = {
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25
}
local S = {
    {14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, 4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13},
    {15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5, 0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9},
    {10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, 13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12},
    {7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, 10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14},
    {2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, 4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3},
    {12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, 9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13},
    {4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, 1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12},
    {13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, 7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11}
}
local PC1 = {
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35, 27, 19, 11, 3,
    60, 52, 44, 36, 63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37,
    29, 21, 13, 5, 28, 20, 12, 4
}
local PC2 = {
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10, 23, 19, 12, 4, 26, 8, 16, 7,
    27, 20, 13, 2, 41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48, 44, 49, 39, 56,
    34, 53, 46, 42, 50, 36, 29, 32
}
local SHIFTS = {1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1}

-- ===== Helper functions =====
local function string_to_bytes(str)
    local bytes = {}
    for i = 1, #str do
        bytes[i] = string.byte(str, i)
    end
    return bytes
end

local function bytes_to_string(bytes)
    return string.char(table.unpack(bytes))
end

local function permute(block, table_p)
    local result = 0
    for i = 1, #table_p do
        result = (result << 1) | ((block >> (64 - table_p[i])) & 1)
    end
    return result
end

local function permute_48(block, table_p)
    local result = 0
    for i = 1, #table_p do
        result = (result << 1) | ((block >> (56 - table_p[i])) & 1)
    end
    return result
end

local function sbox_substitute(block)
    local result = 0
    for i = 1, 8 do
        local six_bits = (block >> (48 - i * 6)) & 63
        local row = ((six_bits >> 5) << 1) | (six_bits & 1)
        local col = (six_bits >> 1) & 15
        result = (result << 4) | S[i][row * 16 + col + 1]
    end
    return result
end

local function bytes_to_words(bytes, offset)
    offset = offset or 1
    local words = {}
    for i = 0, 3 do
        local b1 = bytes[offset + i * 4] or 0
        local b2 = bytes[offset + i * 4 + 1] or 0
        local b3 = bytes[offset + i * 4 + 2] or 0
        local b4 = bytes[offset + i * 4 + 3] or 0
        words[i + 1] = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    end
    return words
end

local function words_to_bytes(words)
    local bytes = {}
    for i = 1, #words do
        local w = words[i]
        bytes[#bytes + 1] = (w >> 24) & 0xFF
        bytes[#bytes + 1] = (w >> 16) & 0xFF
        bytes[#bytes + 1] = (w >> 8) & 0xFF
        bytes[#bytes + 1] = w & 0xFF
    end
    return bytes
end

local function rotl16(x, n)
    return ((x << (n & 0x0F)) | (x >> (16 - (n & 0x0F)))) & 0xFFFF
end

local function rotr16(x, n)
    return ((x >> (n & 0x0F)) | (x << (16 - (n & 0x0F)))) & 0xFFFF
end

-- ===== RC4 =====
crypto.rc4 = {
    encrypt = function(key, data)
        local key_bytes = string_to_bytes(key)
        local s = {}
        for i = 0, 255 do
            s[i] = i
        end

        local j = 0
        for i = 0, 255 do
            j = (j + s[i] + key_bytes[i % #key_bytes + 1]) % 256
            s[i], s[j] = s[j], s[i]
        end

        local result = {}
        local i, j_p = 0, 0
        for k = 1, #data do
            i = (i + 1) % 256
            j_p = (j_p + s[i]) % 256
            s[i], s[j_p] = s[j_p], s[i]
            result[k] = string.byte(data, k) ~ s[(s[i] + s[j_p]) % 256]
        end
        return bytes_to_string(result)
    end,

    decrypt = function(key, data)
        return crypto.rc4.encrypt(key, data)
    end
}

-- ===== RC2 =====
crypto.rc2 = {
    expand_key = function(key, key_bits)
        key_bits = key_bits or 128
        local key_bytes = string_to_bytes(key)

        for i = #key_bytes + 1, 128 do
            key_bytes[i] = PI[(key_bytes[i - #key_bytes] + i - #key_bytes) & 0xFF]
        end

        if key_bits < 256 then
            local key_length = math.floor((key_bits + 7) / 8)
            if key_length <= 128 then
                key_bytes[key_length] = PI[key_bytes[key_length] & 0xFF] & (0xFF >> (8 - (key_bits % 8)))
            end
            for i = key_length + 1, 128 do
                key_bytes[i] = PI[key_bytes[i - 1] & 0xFF]
            end
        end

        local expanded = {}
        for i = 0, 63 do
            expanded[i + 1] = (key_bytes[i * 2 + 1] << 8) | (key_bytes[i * 2 + 2] & 0xFF)
        end
        return expanded
    end,

    encrypt_block = function(key_schedule, plaintext)
        local words = bytes_to_words(string_to_bytes(plaintext))
        local R0, R1, R2, R3 = words[1], words[2], words[3], words[4]
        local idx = 1

        for round = 1, 2 do
            for r = 1, 8 do
                R0 = rotl16((R0 + key_schedule[idx] + (R1 & R2) | ((~R1) & R3)) & 0xFFFF, 1)
                R1 = rotl16((R1 + key_schedule[idx + 1] + (R2 & R3) | ((~R2) & R0)) & 0xFFFF, 2)
                R2 = rotl16((R2 + key_schedule[idx + 2] + (R3 & R0) | ((~R3) & R1)) & 0xFFFF, 3)
                R3 = rotl16((R3 + key_schedule[idx + 3] + (R0 & R1) | ((~0) & R2)) & 0xFFFF, 5)
                idx = idx + 4
            end
        end

        return words_to_bytes({R0, R1, R2, R3})
    end,

    decrypt_block = function(key_schedule, ciphertext)
        local words = bytes_to_words(string_to_bytes(ciphertext))
        local R0, R1, R2, R3 = words[1], words[2], words[3], words[4]
        local idx = 64

        local key_rev = {}
        for k = 1, 64 do
            key_rev[k] = key_schedule[65 - k]
        end

        for round = 1, 2 do
            for r = 1, 8 do
                R3 = (rotr16(R3, 5) - (R0 & R1) | ((~R0) & R2) - key_rev[idx]) & 0xFFFF
                R2 = (rotr16(R2, 3) - (R3 & R0) | ((~R3) & R1) - key_rev[idx + 1]) & 0xFFFF
                R1 = (rotr16(R1, 2) - (R2 & R3) | ((~0) & R0) - key_rev[idx + 2]) & 0xFFFF
                R0 = (rotr16(R0, 1) - (R1 & R2) | ((~R1) & R3) - key_rev[idx + 3]) & 0xFFFF
                idx = idx - 4
            end
        end

        return words_to_bytes({R0, R1, R2, R3})
    end,

    encrypt = function(key, data, key_bits)
        local key_schedule = crypto.rc2.expand_key(key, key_bits)

        local pad_len = 8 - (#data % 8)
        local padded = data .. string.rep(string.char(pad_len), pad_len)

        local result = {}
        for i = 1, #padded, 8 do
            result[#result + 1] = bytes_to_string(crypto.rc2.encrypt_block(key_schedule, padded:sub(i, i + 7)))
        end
        return table.concat(result)
    end,

    decrypt = function(key, data, key_bits)
        local key_schedule = crypto.rc2.expand_key(key, key_bits)

        local result = {}
        for i = 1, #data, 8 do
            result[#result + 1] = bytes_to_string(crypto.rc2.decrypt_block(key_schedule, data:sub(i, i + 7)))
        end

        local plaintext = table.concat(result)
        return plaintext:sub(1, #plaintext - string.byte(plaintext, #plaintext))
    end
}

-- ===== DES & 3DES =====
crypto.des = {
    generate_keys = function(key)
        local key_num = 0
        for i = 1, 8 do
            key_num = (key_num << 8) | string.byte(key, i)
        end

        local k = permute_48(key_num, PC1)
        local C = (k >> 28) & 0x0FFFFFFF
        local D = k & 0x0FFFFFFF

        local round_keys = {}
        for i = 1, 16 do
            local shift = SHIFTS[i]
            C = ((C << shift) | (C >> (28 - shift))) & 0x0FFFFFFF
            D = ((D << shift) | (D >> (28 - shift))) & 0x0FFFFFFF
            round_keys[i] = permute_48((C << 28) | D, PC2)
        end
        return round_keys
    end,

    encrypt_block = function(key, plaintext)
        local round_keys = crypto.des.generate_keys(key)

        local block = 0
        for i = 1, 8 do
            block = (block << 8) | string.byte(plaintext, i)
        end

        block = permute(block, IP)
        local L = (block >> 32) & 0xFFFFFFFF
        local R = block & 0xFFFFFFFF

        for i = 1, 16 do
            local oldL = L

            local expanded = 0
            for j = 1, 48 do
                expanded = (expanded << 1) | ((R >> (32 - E[j])) & 1)
            end

            local substituted = sbox_substitute(expanded ~ round_keys[i])

            local permuted = 0
            for j = 1, 32 do
                permuted = (permuted << 1) | ((substituted >> (32 - P[j])) & 1)
            end

            L = R
            R = oldL ~ permuted
        end

        local ciphertext_num = permute((R << 32) | L, IP_INV)

        local ciphertext = ""
        for i = 1, 8 do
            ciphertext = ciphertext .. string.char((ciphertext_num >> (64 - i * 8)) & 0xFF)
        end

        return ciphertext
    end,

    decrypt_block = function(key, ciphertext)
        local round_keys = crypto.des.generate_keys(key)

        local block = 0
        for i = 1, 8 do
            block = (block << 8) | string.byte(ciphertext, i)
        end

        block = permute(block, IP)
        local L = (block >> 32) & 0xFFFFFFFF
        local R = block & 0xFFFFFFFF

        for i = 16, 1, -1 do
            local oldL = L

            local expanded = 0
            for j = 1, 48 do
                expanded = (expanded << 1) | ((R >> (32 - E[j])) & 1)
            end

            local substituted = sbox_substitute(expanded ~ round_keys[i])

            local permuted = 0
            for j = 1, 32 do
                permuted = (permuted << 1) | ((substituted >> (32 - P[j])) & 1)
            end

            L = R
            R = oldL ~ permuted
        end

        local plaintext_num = permute((R << 32) | L, IP_INV)

        local plaintext = ""
        for i = 1, 8 do
            plaintext = plaintext .. string.char((plaintext_num >> (64 - i * 8)) & 0xFF)
        end

        return plaintext
    end,

    encrypt = function(key, data)
        local pad_len = 8 - (#data % 8)
        local padded = data .. string.rep(string.char(pad_len), pad_len)

        local result = {}
        for i = 1, #padded, 8 do
            result[#result + 1] = crypto.des.encrypt_block(key, padded:sub(i, i + 7))
        end

        return table.concat(result)
    end,

    decrypt = function(key, data)
        local result = {}
        for i = 1, #data, 8 do
            result[#result + 1] = crypto.des.decrypt_block(key, data:sub(i, i + 7))
        end

        local plaintext = table.concat(result)
        return plaintext:sub(1, #plaintext - string.byte(plaintext, #plaintext))
    end,

    des3_encrypt = function(key, data)
        local k1 = key:sub(1, 8)
        local k2 = key:sub(9, 16)
        local k3 = #key == 24 and key:sub(17, 24) or k1

        return crypto.des.encrypt(k3, crypto.des.decrypt(k2, crypto.des.encrypt(k1, data)))
    end,

    des3_decrypt = function(key, data)
        local k1 = key:sub(1, 8)
        local k2 = key:sub(9, 16)
        local k3 = #key == 24 and key:sub(17, 24) or k1

        return crypto.des.decrypt(k1, crypto.des.encrypt(k2, crypto.des.decrypt(k3, data)))
    end
}

-- ===== MD2 =====
crypto.md2 = function(input)
    local bytes = string_to_bytes(input)

    local pad_len = 16 - (#bytes % 16)
    for i = 1, pad_len do
        bytes[#bytes + 1] = pad_len
    end

    local checksum = {}
    for i = 1, 16 do
        checksum[i] = 0
    end

    local l = 0
    for i = 1, #bytes, 16 do
        for j = 0, 15 do
            checksum[j + 1] = PI[(checksum[j + 1] ~ l ~ bytes[i + j]) & 0xFF]
            l = checksum[j + 1]
        end
    end

    for i = 1, 16 do
        bytes[#bytes + 1] = checksum[i]
    end

    local X = {}
    for i = 1, 48 do
        X[i] = 0
    end

    for i = 1, #bytes, 16 do
        for j = 0, 15 do
            X[j + 1] = bytes[i + j]
            X[j + 17] = X[j + 1]
            X[j + 33] = X[j + 1] ~ X[j + 17]
        end

        for j = 1, 18 do
            for k = 0, 47 do
                X[k + 1] = PI[X[k + 1] & 0xFF]
            end
            X[1] = X[1] ~ j
        end
    end

    local hash = {}
    for i = 1, 16 do
        hash[i] = X[i]
    end

    return bytes_to_string(hash)
end

-- ===== MD4 =====
crypto.md4 = function(input)
    local bytes = string_to_bytes(input)
    local bit_len = #bytes * 8

    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do
        bytes[#bytes + 1] = 0
    end

    for i = 1, 8 do
        bytes[#bytes + 1] = (bit_len >> (8 * (i - 1))) & 0xFF
    end

    local A, B, C, D = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476

    local function F(x, y, z)
        return (x & y) | ((~x) & z)
    end

    local function G(x, y, z)
        return (x & y) | (x & z) | (y & z)
    end

    local function H(x, y, z)
        return x ~ y ~ z
    end

    local function rotl(x, n)
        return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF
    end

    for i = 1, #bytes, 64 do
        local M = {}
        for j = 0, 15 do
            M[j + 1] = (bytes[i + j * 4 + 3] << 24) |
                       (bytes[i + j * 4 + 2] << 16) |
                       (bytes[i + j * 4 + 1] << 8) |
                       bytes[i + j * 4]
        end

        local a, b, c, d = A, B, C, D

        local function round1(a1, b1, c1, d1, k, s)
            return rotl((a1 + F(b1, c1, d1) + M[k]) & 0xFFFFFFFF, s)
        end

        local function round2(a1, b1, c1, d1, k, s)
            return rotl((a1 + G(b1, c1, d1) + M[k] + 0x5A827999) & 0xFFFFFFFF, s)
        end

        local function round3(a1, b1, c1, d1, k, s)
            return rotl((a1 + H(b1, c1, d1) + M[k] + 0x6ED9EBA1) & 0xFFFFFFFF, s)
        end

        a = round1(a, b, c, d, 1, 3)
        d = round1(d, a, b, c, 2, 7)
        c = round1(c, d, a, b, 3, 11)
        b = round1(b, c, d, a, 4, 19)

        a = round1(a, b, c, d, 5, 3)
        d = round1(d, a, b, c, 6, 7)
        c = round1(c, d, a, b, 7, 11)
        b = round1(b, c, d, a, 8, 19)

        a = round1(a, b, c, d, 9, 3)
        d = round1(d, a, b, c, 10, 7)
        c = round1(c, d, a, b, 11, 11)
        b = round1(b, c, d, a, 12, 19)

        a = round1(a, b, c, d, 13, 3)
        d = round1(d, a, b, c, 14, 7)
        c = round1(c, d, a, b, 15, 11)
        b = round1(b, c, d, a, 16, 19)

        a = round2(a, b, c, d, 1, 3)
        d = round2(d, a, b, c, 5, 5)
        c = round2(c, d, a, b, 9, 9)
        b = round2(b, c, d, a, 13, 13)

        a = round2(a, b, c, d, 2, 3)
        d = round2(d, a, b, c, 6, 5)
        c = round2(c, d, a, b, 10, 9)
        b = round2(b, c, d, a, 14, 13)

        a = round2(a, b, c, d, 3, 3)
        d = round2(d, a, b, c, 7, 5)
        c = round2(c, d, a, b, 11, 9)
        b = round2(b, c, d, a, 15, 13)

        a = round2(a, b, c, d, 4, 3)
        d = round2(d, a, b, c, 8, 5)
        c = round2(c, d, a, b, 12, 9)
        b = round2(b, c, d, a, 16, 13)

        a = round3(a, b, c, d, 1, 3)
        d = round3(d, a, b, c, 9, 9)
        c = round3(c, d, a, b, 5, 11)
        b = round3(b, c, d, a, 13, 15)

        a = round3(a, b, c, d, 2, 3)
        d = round3(d, a, b, c, 10, 9)
        c = round3(c, d, a, b, 6, 11)
        b = round3(b, c, d, a, 14, 15)

        a = round3(a, b, c, d, 3, 3)
        d = round3(d, a, b, c, 11, 9)
        c = round3(c, d, a, b, 7, 11)
        b = round3(b, c, d, a, 15, 15)

        a = round3(a, b, c, d, 4, 3)
        d = round3(d, a, b, c, 12, 9)
        c = round3(c, d, a, b, 8, 11)
        b = round3(b, c, d, a, 16, 15)

        A = (A + a) & 0xFFFFFFFF
        B = (B + b) & 0xFFFFFFFF
        C = (C + c) & 0xFFFFFFFF
        D = (D + d) & 0xFFFFFFFF
    end

    local hash = {}
    for i = 0, 3 do
        hash[#hash + 1] = (A >> (8 * i)) & 0xFF
        hash[#hash + 1] = (B >> (8 * i)) & 0xFF
        hash[#hash + 1] = (C >> (8 * i)) & 0xFF
        hash[#hash + 1] = (D >> (8 * i)) & 0xFF
    end

    return bytes_to_string(hash)
end

-- ===== MD5 =====
crypto.md5 = function(input)
    local bytes = string_to_bytes(input)
    local bit_len = #bytes * 8

    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do
        bytes[#bytes + 1] = 0
    end

    for i = 1, 8 do
        bytes[#bytes + 1] = (bit_len >> (8 * (i - 1))) & 0xFF
    end

    local A, B, C, D = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476

    local function F(x, y, z)
        return (x & y) | ((~x) & z)
    end

    local function G(x, y, z)
        return (x & z) | (y & (~z))
    end

    local function H(x, y, z)
        return x ~ y ~ z
    end

    local function I(x, y, z)
        return y ~ (x | (~z))
    end

    local function rotl(x, n)
        return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF
    end

    local S = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    }

    local T = {}
    for i = 1, 64 do
        T[i] = math.floor(2^32 * math.abs(math.sin(i))) & 0xFFFFFFFF
    end

    for i = 1, #bytes, 64 do
        local M = {}
        for j = 0, 15 do
            M[j + 1] = (bytes[i + j * 4 + 3] << 24) |
                       (bytes[i + j * 4 + 2] << 16) |
                       (bytes[i + j * 4 + 1] << 8) |
                       bytes[i + j * 4]
        end

        local a, b, c, d = A, B, C, D

        for j = 1, 64 do
            local f, g

            if j <= 16 then
                f = F(b, c, d)
                g = j - 1
            elseif j <= 32 then
                f = G(b, c, d)
                g = (5 * j - 4) % 16
            elseif j <= 48 then
                f = H(b, c, d)
                g = (3 * j + 2) % 16
            else
                f = I(b, c, d)
                g = (7 * j - 7) % 16
            end

            local new_a = (a + f + M[g + 1] + T[j]) & 0xFFFFFFFF
            a, b, c, d = d, (b + rotl(new_a, S[j])) & 0xFFFFFFFF, b, c
        end

        A = (A + a) & 0xFFFFFFFF
        B = (B + b) & 0xFFFFFFFF
        C = (C + c) & 0xFFFFFFFF
        D = (D + d) & 0xFFFFFFFF
    end

    local hash = {}
    for i = 0, 3 do
        hash[#hash + 1] = (A >> (8 * i)) & 0xFF
        hash[#hash + 1] = (B >> (8 * i)) & 0xFF
        hash[#hash + 1] = (C >> (8 * i)) & 0xFF
        hash[#hash + 1] = (D >> (8 * i)) & 0xFF
    end

    return bytes_to_string(hash)
end

return crypto
