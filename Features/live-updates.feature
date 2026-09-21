# language: en
Feature: Keep Komodo resources up to date
  As an operator of a Komodo instance
  I want live resource updates and a clear connection status
  so that I can trust the state shown by Varan.

  Scenario: Connect to live updates
    Given I have selected a saved connection with API key or JWT credentials
    When Varan connects to Komodo's update WebSocket
    Then I see whether it is connecting, live, or offline
    And the status does not imply that WebSocket events arrive on a polling schedule

  Scenario: Refresh affected resources
    Given the live update connection is authenticated
    When Komodo completes an update for a server or stack
    Then Varan reloads the affected server, stack, and container state
    And unrelated resource details remain unchanged

  Scenario: Recover the canonical state
    Given the live update connection was interrupted or the app was in the background
    When Varan reconnects in the foreground
    Then it reloads the complete canonical state for the active view
    And only one live connection exists for the active profile

  Scenario: Poll metrics independently
    Given a resource detail view is visible in the foreground
    When I select a metric refresh interval
    Then metrics refresh at that interval without relying on WebSocket events
    And polling stops when the app leaves the foreground
