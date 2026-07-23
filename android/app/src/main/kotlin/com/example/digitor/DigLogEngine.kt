package com.example.digitor

interface DigLogEngine {
    val actualBitDepth: Int
    val codecName: String
    fun start()
    fun stop(): Boolean
    fun outputIsValid(): Boolean
}
