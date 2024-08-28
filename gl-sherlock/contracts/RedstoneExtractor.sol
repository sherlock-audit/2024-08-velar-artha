pragma solidity ^0.8.4;

import "./vendor/data-services/PrimaryProdDataServiceConsumerBase.sol";

contract RedstoneExtractor is PrimaryProdDataServiceConsumerBase {
  function extractPrice(bytes32 feedId, bytes calldata)
      public view returns(uint256, uint256)
  {
    bytes32[] memory dataFeedIds = new bytes32[](1);
    dataFeedIds[0] = feedId;
    (uint256[] memory values, uint256 timestamp) =
        getOracleNumericValuesAndTimestampFromTxMsg(dataFeedIds);
    validateTimestamp(timestamp); //!!!
    return (values[0], timestamp);
  }
}

// eof
