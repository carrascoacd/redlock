defmodule Redlock do

  @moduledoc ~S"""
  This library is an implementation of Redlock (Redis destributed lock)

  [Redlock](https://redis.io/topics/distlock)

  ## Usage

      resource = "example_key:#{user_id}"
      lock_exp_sec = 10

      case Redlock.lock(resource, lock_exp_sec) do

        {:ok, mutex} ->
          # some other code which write and read on RDBMS, KVS or other storage
          # call unlock finally
          Redlock.unlock(resource, mutex)

        :error ->
          Logger.error "failed to lock resource. maybe redis connection got trouble."
          {:error, :system_error}

      end

  Or you can use `transaction` function

      def my_function() do
        # do something, and return {:ok, :my_result} or {:error, :my_error}
      end

      def execute_with_lock() do

        resource = "example_key:#{user_id}"
        lock_exp_sec = 10

        case Redlock.transaction(resource, lock_exp_sec, &my_function/0) do

          {:ok, :my_result} ->
            Logger.info "this is the return-value of my_function/0"
            :ok

          {:error, :my_error} ->
            Logger.info "this is the return-value of my_function/0"
            :error

          {:error, :lock_failure} ->
            Logger.info "if locking has failed, Redlock returns this error"
            :error

        end
      end

  ## Setup

      children = [
        # other workers/supervisors

        Redlock.child_spec(redlock_opts)
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Options

  Single Node Mode

      readlock_opts = [

        pool_size:             2,
        drift_factor:          0.01,
        max_retry:             3,
        retry_interval:        300,
        reconnection_interval: 5_000,

        # you must set odd number of server
        servers: [
          [host: "redis1.example.com", port: 6379],
          [host: "redis2.example.com", port: 6379],
          [host: "redis3.example.com", port: 6379]
        ]

      ]

  - `pool_size`: pool_size of number of connection pool for each Redis master node, default is 2
  - `drift_factor`: number used for calculating validity for results, see https://redis.io/topics/distlock for more detail.
  - `max_retry`: how many times you want to retry if you failed to lock resource.
  - `retry_interval`: (milliseconds) how long you want to wait untill your next try after a lock-failure.
  - `reconnection_interval`: (milliseconds) how long you want to wait untill your next try after a redis-disconnection.
  - `servers`: host and port settings for each redis-server. this amount must be odd.

  Cluster Mode

      readlock_opts = [

        pool_size:             2,
        drift_factor:          0.01,
        max_retry:             3,
        retry_interval:        300,
        reconnection_interval: 5_000,

        cluster: [
          # first node
          [
            # you must set odd number of server
            [host: "redis1.example.com", port: 6379],
            [host: "redis2.example.com", port: 6379],
            [host: "redis3.example.com", port: 6379]
          ],
          # second node
          [
            # you must set odd number of server
            [host: "redis4.example.com", port: 6379],
            [host: "redis5.example.com", port: 6379],
            [host: "redis6.example.com", port: 6379]
          ],
          # third node
          [
            # you must set odd number of server
            [host: "redis7.example.com", port: 6379],
            [host: "redis8.example.com", port: 6379],
            [host: "redis9.example.com", port: 6379]
          ]
        ]

      ]

  Set `cluster` option instead of `servers`, then Redlock works as cluster mode.
  When you want to lock some resource, Redlock chooses a node depends on a resource key with consistent-hashing.

  """

  def child_spec(opts) do
    import Supervisor.Spec
    supervisor(Redlock.TopSupervisor, [opts])
  end

  def transaction(resource, ttl, callback) do
    case Redlock.Executor.lock(resource, ttl) do

      {:ok, mutex} ->
        try do
          callback.()
        after
          Redlock.Executor.unlock(resource, mutex)
        end

      :error ->
        {:error, :lock_failure}

    end
  end

  def lock(resource, ttl) do
    Redlock.Executor.lock(resource, ttl)
  end

  def unlock(resource, value) do
    Redlock.Executor.unlock(resource, value)
  end

end
