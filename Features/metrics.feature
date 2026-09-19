# language: en
Feature: Monitor resource metrics
  As an operator of a Komodo instance
  I want current and historical resource metrics
  so that I can identify unhealthy servers, stacks, and containers.

  Scenario: View current server metrics
    Given a managed server reports system statistics
    When I open its metrics view
    Then I see CPU, load, memory, disk, and network values
    And I see when the values were last refreshed
    And I see the server polling interval

  Scenario: View historical server metrics
    Given historical statistics exist for a managed server
    When I choose a supported time range
    Then CPU, memory, disk, and network history is displayed in accessible charts
    And each chart also exposes a textual summary

  Scenario: View container metrics
    Given Komodo reports statistics for a container
    When I open the container metrics view
    Then I see CPU, memory, network, block I/O, and process values that are available
    And unsupported values are not presented as zero

  Scenario: View aggregate stack metrics
    Given a stack contains multiple services with container statistics
    When I open the stack metrics view
    Then I see which services contribute to the aggregate values
    And I can navigate from an aggregate value to the contributing containers

  Scenario: Refresh metrics safely
    Given automatic metric refreshing is enabled
    When I leave the metrics view or switch connections
    Then in-flight requests for the previous context are cancelled
    And stale values are not presented as current data

  Scenario: Metrics are unavailable
    Given a server does not support or cannot currently return a metric
    When I open a metrics view
    Then the unavailable metric is clearly identified
    And the remaining resource details stay usable
