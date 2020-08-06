from lisa.util.excutableResult import ExecutableResult
from typing import Optional

import paramiko

from lisa.util.connectionInfo import ConnectionInfo


class SshConnection:
    def __init__(
        self,
        address: str = "",
        port: int = 22,
        publicAddress: str = "",
        publicPort: int = 22,
        username: str = "root",
        password: str = "",
        privateKeyFile: str = "",
    ) -> None:
        self.address = address
        self.port = port
        self.publicAddress = publicAddress
        self.publicPort = publicPort
        self.username = username
        self.password = password
        self.privateKeyFile = privateKeyFile

        if (self.address is None or self.address == "") and (
            self.publicAddress is None or self.publicAddress == ""
        ):
            raise Exception("at least one of address and publicAddress need to be set")
        elif self.address is None or self.address == "":
            self.address = self.publicAddress
        elif self.publicAddress is None or self.publicAddress == "":
            self.publicAddress = self.address

        if (self.port is None or self.port <= 0) and (
            self.publicPort is None or self.publicPort <= 0
        ):
            raise Exception("at least one of port and publicPort need to be set")
        elif self.port is None or self.port <= 0:
            self.port = self.publicPort
        elif self.publicPort is None or self.publicPort <= 0:
            self.publicPort = self.port

        self._connectionInfo = ConnectionInfo(
            self.address, self.port, self.username, self.password, self.privateKeyFile
        )
        self._publicConnectionInfo = ConnectionInfo(
            self.publicAddress,
            self.publicPort,
            self.username,
            self.password,
            self.privateKeyFile,
        )

        self._connection: Optional[paramiko.SSHClient] = None
        self._publicConnection: Optional[paramiko.SSHClient] = None

        self._isConnected: bool = False
        self._isPublicConnected: bool = False

    @property
    def connectionInfo(self) -> ConnectionInfo:
        return self._connectionInfo

    @property
    def publicConnectionInfo(self) -> ConnectionInfo:
        return self._publicConnectionInfo

    def execute(self, cmd: str) -> ExecutableResult:
        client = self.connect()
        _, stdout_file, stderr_file = client.exec_command(cmd)
        exit_code: int = stdout_file.channel.recv_exit_status()

        stdout: str = stdout_file.read().decode("utf-8")
        stderr: str = stderr_file.read().decode("utf-8")
        result = ExecutableResult(stdout, stderr, exit_code)

        return result

    def connect(self, isPublic: bool = True) -> paramiko.SSHClient:
        if isPublic:
            connection = self._publicConnection
            connectionInfo = self.publicConnectionInfo
        else:
            connection = self._connection
            connectionInfo = self.connectionInfo
        if connection is None:
            connection = paramiko.SSHClient()
            connection.set_missing_host_key_policy(paramiko.client.AutoAddPolicy)
            connection.connect(
                connectionInfo.address,
                port=connectionInfo.port,
                username=connectionInfo.username,
                password=connectionInfo.password,
                key_filename=connectionInfo.privateKeyFile,
                look_for_keys=False,
            )
            if isPublic:
                self._publicConnection = connection
            else:
                self._connection = connection
        return connection

    def cleanup(self) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None
        if self._publicConnection is not None:
            self._publicConnection.close()
            self._publicConnection = None
