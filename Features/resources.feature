# language: en
Feature: Browse and manage Komodo resources
  As an operator of a Komodo instance
  I want dedicated server, stack, and container views
  so that I can understand and safely change my infrastructure from Varan.

  Scenario: Navigate between related resources
    Given I have selected a saved and reachable connection
    When I open a server, one of its stacks, and a container in that stack
    Then each resource has a dedicated detail view
    And I can move between the related server, stack, and container
    And the selected connection remains unchanged

  Scenario: Inspect a server
    Given a managed server is reachable
    When I open its detail view
    Then I see its state and system information
    And I see the stacks and containers associated with it
    And unavailable information is distinguished from an empty value

  Scenario: Inspect a stack container
    Given a stack contains a running container
    When I open the container detail view
    Then I see its status, image, ports, volumes, and networks
    And I can open its metrics and logs
    And runtime actions are separate from configuration editing

  Scenario: Update supported stack configuration
    Given I can write to a stack
    When I change a supported configuration field and review the changes
    Then Varan sends only the changed fields through the write API
    And further save actions are disabled while the request is in progress
    And the canonical stack is loaded again after the write succeeds

  Scenario: Update supported server configuration
    Given I can write to a server
    When I change a supported configuration field and review the changes
    Then Varan sends only the changed fields through the write API
    And the canonical server is loaded again after the write succeeds

  Scenario: Edit configuration related to a container
    Given a container is owned by a stack service
    When I choose to edit its configuration
    Then Varan opens the owning stack configuration
    And Varan does not treat the ephemeral container as an independent configuration source

  Scenario: Write permission is missing
    Given I can read a resource but cannot write to it
    When I attempt to save a change
    Then the permission failure is explained without discarding my input
    And the resource remains available in read-only form
