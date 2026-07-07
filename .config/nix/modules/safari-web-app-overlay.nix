final: prev: {
  safari-web-app-slack = final.callPackage ../pkgs/safari-web-app {
    name = "Slack";
    url = "https://app.slack.com";
  };
}
