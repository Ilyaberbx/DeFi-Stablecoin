include .env

PHONY: deploy

deploy-sepolia:
	@forge script script/DeployDSCSystem.s.sol:DeployDSCSystem --rpc-url $(SEPOLIA_RPC_URL) --broadcast --account illiaSepolia --verify -vvvv