This is a Single master I2C system

I2C_slave is a I2C slave interface, and can be instantiated inside a slave device
slave_1 is one example of slave device, which address is 25
Thus, different device can have different amount of memory inside, and different read/write policy

I2C_master is a I2C master interface, and it is now connected directly to the testbench
It receives instructions and data into a FIFO and send them through I2C interface
For write instruction, the first byte is address and R/W, and the following bytes are data to write
For read instruction, the first byte is address and R/W, and the following bytes are don't care term, but the amount of bytes is the amount of bytes to read
The master can detect SDA error transfering START, address, and STOP, and will resend if error happens
The master can detect SCL stretching, when SCL remains LOW, master will pause the transaction

I2C_tb
define NO_ACK will make slave send no ACK in 50 SCL cycles(can change the number inside I2C_slave)
define SDA_INTERRUPT will pull SDA to low for 50 SCL cycles(can change the number inside I2C_tb)
define SCL_STRETCH will pull SCL to low for 200 CLK cycles(can change the number inside I2C_tb)

*Not receiving an ACK is treated as broken pipe, slave will go to IDLE state, and master will restart the transfer

**What is NOT implemented inside the modules
*10-bit address
*Slave SCL stretching
*Error detection and correction when tranfering data