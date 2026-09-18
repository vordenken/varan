# language: en
Feature: Connect to a Komodo instance
  As an operator of a Komodo instance
  I want to validate my connection securely
  so that I only continue with valid credentials.

  Scenario: Validate a valid API key
    Given a reachable Komodo instance with a valid API key and secret
    When I test the connection
    Then the server profile is selected
    And the stack overview is opened
    And the server profile is saved locally without credentials
    And the credentials are stored in the Keychain

  Scenario: Reject an insecure external server
    Given I enter an external HTTP address
    When I test the connection
    Then the address is rejected without a network request

  Scenario: Display the example address as a placeholder only
    Given I open a new connection
    Then "https://komodo.example.com" is displayed only as the empty-field example
    When I enter a server address
    Then the example address is no longer displayed

  Scenario: Explain rejected credentials
    Given the Komodo instance rejects my credentials
    When I test the connection
    Then a clear error message is displayed
    And no secret is included in the error message

  Scenario: Edit a saved connection
    Given I have a saved connection with credentials
    When I select "Edit" for that connection and validate it successfully
    Then the profile and credentials are updated
    And the existing Keychain reference is retained

  Scenario: Open actions for a saved connection
    Given I have saved a connection
    When I press and hold the connection
    Then I can edit or delete the connection

  Scenario: Detect an invalid JWT
    Given a connection uses an expired or invalid JWT
    When the Komodo instance rejects authentication
    Then the token is explicitly reported as expired or invalid

  Scenario Outline: Distinguish network errors
    Given the Komodo instance is unreachable because of <cause>
    When I make a request
    Then <message> is displayed

    Examples:
      | cause                      | message                                         |
      | no network connection      | There is currently no network connection.      |
      | request timeout             | The server did not respond in time.            |

  Scenario: Change profiles during a request
    Given a request for one connection is still in progress
    When I switch to another profile
    Then the old request is cancelled
    And its cancellation is not displayed as a connection error