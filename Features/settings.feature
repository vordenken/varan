# language: en
Feature: Configure application preferences
  As a Varan user
  I want shared application settings
  so that refresh behavior is consistent across resource views.

  Scenario: Change refresh preferences
    Given automatic metric and log refreshing is enabled
    When I change their intervals in application settings
    Then visible resource views use the selected intervals
    And the preferences remain available after restarting Varan

  Scenario: Manage Komodo instances
    Given I have opened the application settings
    When I add, edit, or remove a Komodo instance
    Then the saved profile is updated in the application
    And its credentials remain protected by the system Keychain
    And I can select the active instance from a resource tab

  Scenario: Disable live updates
    Given a Komodo profile has an active live connection
    When I disable live updates in application settings
    Then the WebSocket connection is closed
    And manual resource refreshing remains available

  Scenario: Choose the initial resource section
    Given I select a default resource section in application settings
    When I open a connection
    Then Varan initially displays that resource section

  Scenario: Reset application settings
    Given I have changed application preferences
    When I confirm restoring the defaults
    Then only application preferences are reset
    And profiles, credentials, and Komodo configuration remain unchanged
