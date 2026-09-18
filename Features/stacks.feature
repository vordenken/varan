# language: en
Feature: View stacks
  As an operator of a Komodo instance
  I want to see the state of my stacks
  so that I can assess operations quickly.

  Scenario: Load stacks from a saved connection
    Given I have selected a saved and reachable connection
    When the stack overview is opened
    Then the name, host, and state of every stack are displayed

  Scenario: Search the stack list
    Given multiple stacks have been loaded
    When I search for a stack name or host
    Then only matching stacks are displayed

  Scenario: Credentials are missing
    Given the server profile exists without associated credentials
    When the stack overview is opened
    Then a clear error with a retry action is displayed

  Scenario: View stack details
    Given a stack with multiple services has been loaded
    When I open the stack
    Then I see its state, host, and containers with name, image, and status

  Scenario: Return from a stack to the stack overview
    Given I have opened a stack from a connection
    When I navigate back within stack navigation
    Then the stack overview for the same connection is displayed
    And the connection remains selected

  Scenario: Stop a stack
    Given a stack is running
    When I select the stop action
    Then I must confirm stopping it
    And further actions are disabled while the request is in progress
    And the server state is reloaded after it is accepted successfully

  Scenario: Start an individual service
    Given a service in the stack is stopped
    When I select the action to start that service
    Then only that service is started
    And the server state is reloaded afterwards

  Scenario: Read a service's logs
    Given a stack contains a reachable service
    When I open the service log view
    Then the navigation bar remains stable while it opens
    And the stream selector and search field are in their final positions while loading
    And the appearance of the search field does not change after loading
    And the search field uses Liquid Glass on supported iOS versions
    And the service heading remains visible
    And a bounded log output with timestamps is visible
    And I can select, search, and copy stdout and stderr
    And search shows the match count and highlighted matches
    And input remains responsive for large logs
    And automatic refreshing ends when I leave the view

  Scenario: Control log refreshing
    Given I have opened a service log view
    When I open the log settings
    Then I can control automatic refreshing and following new lines independently
    And I can refresh the logs immediately regardless of those settings