const { withInfoPlist } = require("expo/config-plugins");

module.exports = function withLys(config) {
  return withInfoPlist(config, (result) => {
    result.modResults.LysTestKit = true;
    return result;
  });
};
