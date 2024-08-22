import { ethers, upgrades } from 'hardhat'

const main = async () => {
  try {
    const signers = await ethers.getSigners()

    const owner = signers[0]
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
    console.log('B token address', usdt.target)
    console.log('staking address', staking.target)
    console.log('A token address', token.target)
  } catch (e) {
    console.log(e)
  }
}
main()
