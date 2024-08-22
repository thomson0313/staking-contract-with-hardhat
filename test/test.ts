import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { expect } from 'chai'
import { ethers, upgrades } from 'hardhat'

const sleep = async (time: number) => {
  new Promise((resolve) => setTimeout(resolve, time))
}

const DECIMALS = 10n ** 18n
describe('Staking', () => {
  const deployStakingContract = async () => {
    const signers = await ethers.getSigners()

    const owner = signers[0]
    const payer = signers[1]
    const [, , user1, user2] = signers
    const Library = await ethers.getContractFactory('IterableMapping')
    const library = await Library.deploy()
    const token = await ethers.deployContract('Token')
    await token.waitForDeployment()
    const Usdt = await ethers.getContractFactory('MockMint')
    const usdt = await Usdt.deploy()

    const stakingArgs = [token.target, usdt.target]

    const staking = await upgrades.deployProxy(
      await ethers.getContractFactory('StakingManagerV3'),
      stakingArgs
    )
    await staking.waitForDeployment()
    await token.transfer(user1.address, 100n * DECIMALS)
    await token.transfer(user2.address, 100n * DECIMALS)
    await usdt.transfer(staking.target, 2000n * DECIMALS)

    return { usdt, token, owner, user1, user2, staking }
  }

  it('Should deposit correct token', async () => {
    const { token, usdt, user1, staking } = await loadFixture(
      deployStakingContract
    )
    await usdt.approve(staking.target, ethers.parseEther('4000'))
    const startTime = new Date().getTime() / 1000 - 1
    const endTime = startTime + 100
    await staking.startEpoch(
      Math.floor(startTime),
      Math.floor(endTime),
      ethers.parseEther('4000')
    )
    await token.connect(user1).approve(staking.target, ethers.parseEther('1'))
    await expect(
      await staking.connect(user1).deposit(ethers.parseEther('1'))
    ).to.emit(staking, 'Deposit') // you should change the time option for deploy function
    await expect(await token.balanceOf(user1.address)).to.be.equal(
      ethers.parseEther('99')
    )
  })

  it('Should emit harvest event', async () => {
    const { token, usdt, user1, staking } = await loadFixture(
      deployStakingContract
    )
    await usdt.approve(staking.target, ethers.parseEther('4000'))
    const startTime = new Date().getTime() / 1000 - 1
    const endTime = startTime + 20
    await staking.startEpoch(
      Math.floor(startTime),
      Math.floor(endTime),
      ethers.parseEther('4000')
    )
    await token.connect(user1).approve(staking.target, ethers.parseEther('1'))
    await staking.connect(user1).deposit(ethers.parseEther('1'))
    await sleep(20000)
    await staking.distribute()
    await expect(staking.connect(user1).claim('1')).to.emit(
      // first epoch
      staking,
      'HarvestRewards'
    ) // you should change the time option for deploy function
  })

  it('Should emit Withdraw', async () => {
    const { token, usdt, user1, staking } = await loadFixture(
      deployStakingContract
    )
    await usdt.approve(staking.target, ethers.parseEther('4000'))
    const startTime = new Date().getTime() / 1000 - 1
    const endTime = startTime + 20
    await staking.startEpoch(
      Math.floor(startTime),
      Math.floor(endTime),
      ethers.parseEther('4000')
    )
    await token.connect(user1).approve(staking.target, ethers.parseEther('1'))
    await staking.connect(user1).deposit(ethers.parseEther('1'))
    await sleep(20000)
    await staking.distribute()
    await expect(staking.connect(user1).unstake()).to.emit(
      // first epoch
      staking,
      'Withdraw'
    ) // you should change the time option for deploy function
  })
  it('Should reverted No reward', async () => {
    const { token, usdt, user1, user2, staking } = await loadFixture(
      deployStakingContract
    )
    await usdt.approve(staking.target, ethers.parseEther('4000'))
    const startTime = new Date().getTime() / 1000 - 1
    const endTime = startTime + 20
    await staking.startEpoch(
      Math.floor(startTime),
      Math.floor(endTime),
      ethers.parseEther('4000')
    )
    await token.connect(user1).approve(staking.target, ethers.parseEther('1'))
    await staking.connect(user1).deposit(ethers.parseEther('1'))
    await sleep(20000)
    await staking.distribute()
    await expect(staking.connect(user2).claim('1')).to.be.revertedWith(
      'No reward'
    ) // you should change the time option for deploy function
  })
})
