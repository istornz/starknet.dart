import 'package:starknet/src/presets/udc.g.dart';
import 'package:starknet/starknet.dart';

enum AccountSupportedTxVersion {
  v0,
  v1,
}

class Account {
  Provider provider;
  Signer signer;
  Felt accountAddress;
  Felt chainId;
  AccountSupportedTxVersion supportedTxVersion;

  Account({
    required this.provider,
    required this.signer,
    required this.accountAddress,
    required this.chainId,
    this.supportedTxVersion = AccountSupportedTxVersion.v1,
  });

  /// Get Nonce for account at given [blockId]
  Future<Felt> getNonce([BlockId blockId = BlockId.latest]) async {
    final response = await provider.call(
      request: FunctionCall(
        contractAddress: accountAddress,
        entryPointSelector: getSelectorByName("get_nonce"),
        calldata: [],
      ),
      blockId: blockId,
    );
    return (response.when(error: (error) async {
      if (error.code == 21 && error.message == "Invalid message selector") {
        // Fallback on provider getNonce
        final nonceResp = await provider.getNonce(
          blockId: blockId,
          contractAddress: accountAddress,
        );

        return (nonceResp.when(
          error: (error) {
            throw Exception(
                "Error provider getNonce (${error.code}): ${error.message}");
          },
          result: ((result) {
            return result;
          }),
        ));
      } else {
        throw Exception(
            "Error call get_nonce (${error.code}): ${error.message}");
      }
    }, result: ((result) {
      return result[0];
    })));
  }

  Future<InvokeTransactionResponse> execute({
    required List<FunctionCall> functionCalls,
    Felt? maxFee,
    Felt? nonce,
  }) async {
    nonce = nonce ?? await getNonce();
    maxFee = maxFee ?? defaultMaxFee;

    final signature = signer.signTransactions(
        transactions: functionCalls,
        contractAddress: accountAddress,
        version: supportedTxVersion == AccountSupportedTxVersion.v0 ? 0 : 1,
        chainId: chainId,
        entryPointSelectorName: "__execute__",
        maxFee: maxFee,
        nonce: nonce);

    switch (supportedTxVersion) {
      case AccountSupportedTxVersion.v0:
        final calldata =
            functionCallsToCalldata(functionCalls: functionCalls) + [nonce];

        return provider.addInvokeTransaction(InvokeTransactionRequest(
          invokeTransaction: InvokeTransactionV0(
            contractAddress: accountAddress,
            entryPointSelector: getSelectorByName('__execute__'),
            calldata: calldata,
            maxFee: maxFee,
            signature: signature,
          ),
        ));
      case AccountSupportedTxVersion.v1:
        final calldata = functionCallsToCalldata(functionCalls: functionCalls);

        return provider.addInvokeTransaction(
          InvokeTransactionRequest(
            invokeTransaction: InvokeTransactionV1(
                senderAddress: accountAddress,
                calldata: calldata,
                signature: signature,
                maxFee: maxFee,
                nonce: nonce),
          ),
        );
    }
  }

  Future<DeclareTransactionResponse> declare({
    required CompiledContract compiledContract,
    Felt? maxFee,
    Felt? nonce,
  }) async {
    nonce = nonce ?? await getNonce();
    maxFee = maxFee ?? defaultMaxFee;

    final signature = signer.signDeclareTransaction(
      compiledContract: compiledContract,
      senderAddress: accountAddress,
      chainId: chainId,
    );

    return provider.addDeclareTransaction(
      DeclareTransactionRequest(
        declareTransaction: DeclareTransaction(
          max_fee: maxFee,
          nonce: nonce,
          contractClass: compiledContract.compress(),
          senderAddress: accountAddress,
          signature: signature,
          type: 'DECLARE',
        ),
      ),
    );
  }

  Future<Felt?> deploy({
    required Felt classHash,
    Felt? salt,
    Felt? unique,
    List<Felt>? calldata,
  }) async {
    salt ??= Felt.fromInt(0);
    unique ??= Felt.fromInt(0);
    calldata ??= [];

    final txHash = await Udc(account: this, address: udcAddress)
        .deployContract(classHash, salt, unique, calldata);

    final txReceipt = await account0.provider
        .getTransactionReceipt(Felt.fromHexString(txHash));

    return getDeployedContractAddress(txReceipt);
  }

  Future<Uint256> balance() async =>
      ERC20(account: this, address: ethAddress).balanceOf(accountAddress);

  Future<String> send(
      {required Felt recipient, required Uint256 amount}) async {
    final txHash = await ERC20(account: this, address: ethAddress)
        .transfer(recipient, amount);
    return txHash;
  }

  static Future<DeployAccountTransactionResponse> deployAccount({
    required Signer signer,
    required Provider provider,
    required List<Felt> constructorCalldata,
    Felt? classHash,
    Felt? contractAddressSalt,
    Felt? maxFee,
    Felt? nonce,
  }) async {
    final chainId = (await provider.chainId()).when(
      result: (result) => Felt.fromHexString(result),
      error: (error) => StarknetChainId.testNet,
    );

    classHash = classHash ?? openZeppelinAccountClassHash;
    maxFee = maxFee ?? defaultMaxFee;
    nonce = nonce ?? defaultNonce;
    contractAddressSalt = contractAddressSalt ?? Felt.fromInt(42);

    final signature = signer.signDeployAccountTransactionV1(
      contractAddressSalt: contractAddressSalt,
      classHash: classHash,
      constructorCalldata: constructorCalldata,
      chainId: chainId,
    );

    return provider.addDeployAccountTransaction(DeployAccountTransactionRequest(
        deployAccountTransaction: DeployAccountTransactionV1(
      classHash: classHash,
      signature: signature,
      maxFee: maxFee,
      nonce: nonce,
      contractAddressSalt: contractAddressSalt,
      constructorCalldata: constructorCalldata,
    )));
  }
}

Account getAccount({
  required Felt accountAddress,
  required Felt privateKey,
  Uri? nodeUri,
  Felt? chainId,
}) {
  nodeUri ??= devnetUri;
  chainId ??= StarknetChainId.testNet;

  final provider = JsonRpcProvider(nodeUri: nodeUri);
  final signer = Signer(privateKey: privateKey);

  return Account(
    provider: provider,
    signer: signer,
    accountAddress: accountAddress,
    chainId: StarknetChainId.testNet,
  );
}

Felt? getDeployedContractAddress(GetTransactionReceipt txReceipt) {
  return txReceipt.when(
      result: (r) {
        final contractDeployedEvent = r.events[0];
        var contractAddress = contractDeployedEvent.data?[0];
        return contractAddress;
      },
      error: (e) => throw Exception(e.message));
}
