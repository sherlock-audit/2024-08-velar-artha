
# Velar Artha contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
BOB
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Only standard tokens (without weird traits) will be used.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
n/a but see below re checks and requirements
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
we would only upgrade the oracle extractor as instructed by the oracle provider. fees will be set to something slightly better than industry standard.
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
no
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
liquidation bots are required.
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
we are still experimenting with fee scaling in params.vy

___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
yes sherlock should assume that the sequencer wont go offline
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
No
___

### Q: Please discuss any design choices you made.
all nontrival tradeoffs should be commented in the source files.
___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
Issues related to compromised oracle are out-of-scope
___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
Yes, 4 hours
___

### Q: Please provide links to previous audits (if any).
https://github.com/Thesis-Defense/Security-Audit-Reports/blob/main/PDFs/240717_Thesis_Defense-Velar_Vyper_Smart_Contracts_Security_Audit_Report.pdf
___

### Q: Please list any relevant protocol resources.
source code comments, and familiarity with gmx-style perpdexes
___

### Q: Additional audit information.
the main trickiness is around the funding fee calculation, fees.current_fees() and positions.value()
___



# Audit scope


[gl-sherlock @ 0e291ffee5e1239efbd01a080f393af59772ae47](https://github.com/Velar-co/gl-sherlock/tree/0e291ffee5e1239efbd01a080f393af59772ae47)
- [gl-sherlock/contracts/RedstoneExtractor.sol](gl-sherlock/contracts/RedstoneExtractor.sol)
- [gl-sherlock/contracts/api.vy](gl-sherlock/contracts/api.vy)
- [gl-sherlock/contracts/core.vy](gl-sherlock/contracts/core.vy)
- [gl-sherlock/contracts/fees.vy](gl-sherlock/contracts/fees.vy)
- [gl-sherlock/contracts/math.vy](gl-sherlock/contracts/math.vy)
- [gl-sherlock/contracts/oracle.vy](gl-sherlock/contracts/oracle.vy)
- [gl-sherlock/contracts/params.vy](gl-sherlock/contracts/params.vy)
- [gl-sherlock/contracts/pools.vy](gl-sherlock/contracts/pools.vy)
- [gl-sherlock/contracts/positions.vy](gl-sherlock/contracts/positions.vy)
- [gl-sherlock/contracts/tokens/ERC20Plus.vy](gl-sherlock/contracts/tokens/ERC20Plus.vy)
- [gl-sherlock/contracts/tokens/IERC20Plus.vy](gl-sherlock/contracts/tokens/IERC20Plus.vy)
- [gl-sherlock/contracts/types.vy](gl-sherlock/contracts/types.vy)


